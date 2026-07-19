import AppKit
import SwiftUI

@main
struct KajiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState: AppState
    @State private var projectStore: ProjectStore
    @State private var worktreeStore: WorktreeStore
    private let updateService = UpdateService.shared

    init() {
        DebugFileLog.start()
        DebugFileLog.log("Lifecycle", "KajiApp init started")
        SwiftRunBundleLauncher.relaunchIfNeeded()
        DroidDataMigration.run()
        let environment = AppEnvironment.live
        let projectStore = ProjectStore(persistence: environment.projectPersistence)
        let worktreeStore = WorktreeStore(
            persistence: environment.worktreePersistence,
            projects: projectStore.projects
        )
        let appState = AppState(
            selectionStore: environment.selectionStore,
            terminalViews: environment.terminalViews,
            workspacePersistence: environment.workspacePersistence
        )
        appState.restoreSelection(
            projects: projectStore.projects,
            worktrees: worktreeStore.worktrees
        )
        _appState = State(initialValue: appState)
        _projectStore = State(initialValue: projectStore)
        _worktreeStore = State(initialValue: worktreeStore)
        DebugFileLog.log("Lifecycle", "KajiApp init completed projects=\(projectStore.projects.count)")
    }

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environment(appState)
                .environment(projectStore)
                .environment(worktreeStore)
                .environment(TermyService.shared)
                .environment(KajiConfig.shared)
                .environment(ThemeService.shared)
                .environment(AppTypographySettings.shared)
                .preferredColorScheme(KajiTheme.colorScheme)
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
                .onOpenURL { url in
                    KajiURLCommandHandler.handle(
                        url: url,
                        appState: appState,
                        projectStore: projectStore,
                        worktreeStore: worktreeStore
                    )
                }
                .onAppear {
                    NotificationStore.shared.appState = appState
                    NotificationStore.shared.worktreeStore = worktreeStore
                    NotificationStore.shared.markAllAsRead()
                    ResourceMonitorService.shared.start(appState: appState, projectStore: projectStore)
                    MeetingNotesCoordinator.shared.configure(
                        appState: appState,
                        projectStore: projectStore,
                        worktreeStore: worktreeStore
                    )
                    Task { await MeetingNotesCoordinator.shared.prepare() }
                    Task {
                        await ProjectRemovalService.shared.recoverPendingRemovals(
                            appState: appState,
                            projectStore: projectStore,
                            worktreeStore: worktreeStore
                        )
                    }
                    appDelegate.onTerminate = { [appState] in
                        appState.saveWorkspaces()
                    }
                    appDelegate.hasUnsavedEditorTabs = { [appState] in
                        appState.unsavedEditorTabs()
                    }
                    appState.onProjectsEmptied = { [projectStore, worktreeStore] projectIDs in
                        Task { @MainActor in
                            for id in projectIDs {
                                guard let project = projectStore.projects.first(where: { $0.id == id }) else { continue }
                                _ = await ProjectRemovalService.shared.finalizeAlreadyEmptied(
                                    project: project,
                                    appState: appState,
                                    projectStore: projectStore,
                                    worktreeStore: worktreeStore
                                )
                            }
                        }
                    }
                }
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        .defaultSize(width: 1200, height: 800)
        .commands {
            KajiCommands(
                appState: appState,
                projectStore: projectStore,
                worktreeStore: worktreeStore,
                keyBindings: .shared,
                config: .shared,
                termy: .shared,
                updateService: .shared
            )
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var onTerminate: (() -> Void)?
    var hasUnsavedEditorTabs: (() -> [EditorTabState])?
    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        DebugFileLog.log("Lifecycle", "applicationDidFinishLaunching started")
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        HugeIconFont.registerIfNeeded()
        TerminalBundledFont.registerIfNeeded()
        setAppIcon()
        _ = TermyService.shared
        _ = AppTypographySettings.shared
        ThemeService.shared.applyDefaultThemeIfNeeded()
        MonacoPreloadService.shared.start()
        UpdateService.shared.start()
        ModifierKeyMonitor.shared.start()
        SpeechInputController.shared.start()
        ProviderEventReceiver.shared.start()
        CodexSessionMonitor.shared.start()
        SystemWakeCoordinator.shared.start()
        _ = SleepPreventionController.shared
        Task { await ClosedLidSessionController.shared.probeCapability() }
        _ = CLILauncherSettings.shared
        let gatewayStore = AIGatewaySettingsStore.shared
        if gatewayStore.settings.isEnabled, gatewayStore.settings.autoStart {
            Task {
                await AIGatewayRuntimeController.shared.start(settings: gatewayStore.settings, token: gatewayStore.ensureToken())
            }
        } else {
            AIGatewayRuntimeController.shared.refreshInstallState()
        }
        AIProviderRegistry.shared.installAll()
        _ = AIUsageSettingsStore.isUsageEnabled()
        DebugFileLog.log("Lifecycle", "applicationDidFinishLaunching completed")
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard MeetingNotesCoordinator.shared.requiresTerminationDrain else { return resolveEditorTermination() }
        let unsaved = hasUnsavedEditorTabs?() ?? []
        if !unsaved.isEmpty { return resolveCombinedTermination(unsaved: unsaved) }
        guard confirmsMeetingTermination() else { return .terminateCancel }
        Task { @MainActor in await finishMeetingTermination() }
        return .terminateLater
    }

    @MainActor
    private func resolveCombinedTermination(unsaved: [EditorTabState]) -> NSApplication.TerminateReply {
        let alert = NSAlert()
        alert.messageText = "Save Changes and Stop Meeting Recording?"
        alert.informativeText = "Kaji must finish local transcription and save the meeting before quitting."
        alert.alertStyle = .warning
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "Save All and Quit")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Discard Changes and Quit")
        alert.buttons[0].keyEquivalent = "\r"
        alert.buttons[1].keyEquivalent = "\u{1b}"
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task { @MainActor in
                var failures: [String] = []
                for state in unsaved {
                    do {
                        try await state.saveFileAsync()
                    } catch {
                        failures.append("\(state.fileName): \(error.localizedDescription)")
                    }
                }
                guard failures.isEmpty else {
                    Self.presentSaveFailureAlert(failures: failures)
                    NSApp.reply(toApplicationShouldTerminate: false)
                    return
                }
                await finishMeetingTermination()
            }
            return .terminateLater
        case .alertThirdButtonReturn:
            Task { @MainActor in await finishMeetingTermination() }
            return .terminateLater
        default:
            return .terminateCancel
        }
    }

    @MainActor
    private func confirmsMeetingTermination() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Stop Meeting Recording Before Quitting?"
        alert.informativeText = "Kaji will stop capture, finish the remaining local transcription, "
            + "and save the meeting before quitting."
        alert.alertStyle = .warning
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "Stop and Quit")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].keyEquivalent = "\r"
        alert.buttons[1].keyEquivalent = "\u{1b}"
        return alert.runModal() == .alertFirstButtonReturn
    }

    @MainActor
    private func finishClosedLidTermination() async -> Bool {
        guard await ClosedLidSessionController.shared.shutdownForTermination() else {
            let alert = NSAlert()
            alert.messageText = "Normal Sleep Could Not Be Restored"
            alert.informativeText = "Kaji did not quit because closed-lid protection is still active. Restore normal sleep and try again."
            alert.alertStyle = .critical
            alert.icon = NSApp.applicationIconImage
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return false
        }
        return true
    }

    @MainActor
    private func finishMeetingTermination() async {
        guard await MeetingNotesCoordinator.shared.shutdownForTermination() else {
            let alert = NSAlert()
            alert.messageText = "Meeting Could Not Be Saved"
            alert.informativeText = "Kaji did not quit because the active meeting could not be finalized safely."
            alert.alertStyle = .critical
            alert.icon = NSApp.applicationIconImage
            alert.addButton(withTitle: "OK")
            alert.runModal()
            NSApp.reply(toApplicationShouldTerminate: false)
            return
        }
        guard await finishClosedLidTermination() else {
            NSApp.reply(toApplicationShouldTerminate: false)
            return
        }
        NSApp.reply(toApplicationShouldTerminate: true)
    }

    @MainActor
    private func resolveEditorTermination() -> NSApplication.TerminateReply {
        let unsaved = hasUnsavedEditorTabs?() ?? []
        guard !unsaved.isEmpty else {
            guard ClosedLidSessionController.shared.requiresTerminationDrain else { return .terminateNow }
            Task { @MainActor in
                await NSApp.reply(toApplicationShouldTerminate: finishClosedLidTermination())
            }
            return .terminateLater
        }

        let alert = NSAlert()
        alert.messageText = unsaved.count == 1
            ? "You have unsaved changes in 1 file."
            : "You have unsaved changes in \(unsaved.count) files."
        alert.informativeText = "If you quit without saving, your changes will be lost."
        alert.alertStyle = .warning
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "Save All")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Discard")
        alert.buttons[0].keyEquivalent = "\r"
        alert.buttons[1].keyEquivalent = "\u{1b}"

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            Task { @MainActor in
                var failures: [String] = []
                for state in unsaved {
                    do {
                        try await state.saveFileAsync()
                    } catch {
                        failures.append("\(state.fileName): \(error.localizedDescription)")
                    }
                }
                guard failures.isEmpty else {
                    Self.presentSaveFailureAlert(failures: failures)
                    NSApp.reply(toApplicationShouldTerminate: false)
                    return
                }
                await NSApp.reply(toApplicationShouldTerminate: finishClosedLidTermination())
            }
            return .terminateLater
        case .alertThirdButtonReturn:
            guard ClosedLidSessionController.shared.requiresTerminationDrain else { return .terminateNow }
            Task { @MainActor in
                await NSApp.reply(toApplicationShouldTerminate: finishClosedLidTermination())
            }
            return .terminateLater
        default:
            return .terminateCancel
        }
    }

    @MainActor
    private static func presentSaveFailureAlert(failures: [String]) {
        let alert = NSAlert()
        alert.messageText = failures.count == 1
            ? "Could Not Save File"
            : "Could Not Save \(failures.count) Files"
        alert.informativeText = failures.joined(separator: "\n")
        alert.alertStyle = .warning
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "OK")
        alert.buttons[0].keyEquivalent = "\r"
        alert.runModal()
    }

    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        DebugFileLog.log("Lifecycle", "applicationWillTerminate started")
        AIGatewayRuntimeController.shared.stop()
        onTerminate?()
        AgentRunStore.shared.flushPersistence()
        NotificationStore.shared.saveToDisk()
        SleepPreventionController.shared.stop()
        ClosedLidSessionController.shared.restoreImmediatelyForTermination()
        SystemWakeCoordinator.shared.stop()
        SpeechInputController.shared.stop()
        MeetingNotesSettingsStore.shared.flush()
        CodexSessionMonitor.shared.stop()
        ProviderEventReceiver.shared.stop()
        ParentAgentController.shared.stop()
        BrowserControllerRegistry.closeAllRegisteredImmediately()
        KajiBrowserControlBroker.shared.stop()
        TerminalViewRegistry.shared.removeAll()
        TermyService.shared.shutdown()
        DebugFileLog.log("Lifecycle", "applicationWillTerminate completed")
    }

    @MainActor
    private func setAppIcon() {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") else {
            return
        }
        guard let image = NSImage(contentsOf: url) else { return }
        image.size = NSSize(width: 512, height: 512)
        NSApp.applicationIconImage = image
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

struct WindowConfigurator: NSViewRepresentable {
    let configVersion: Int
    let interfaceModeRaw: String
    let sidebarTransparencyEnabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.identifier = ShortcutContext.mainWindowIdentifier
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.styleMask.insert(.fullSizeContentView)
            w.isMovable = false
            w.isMovableByWindowBackground = false
            Self.applyWindowBackground(
                w,
                interfaceModeRaw: interfaceModeRaw,
                sidebarTransparencyEnabled: sidebarTransparencyEnabled
            )
            Self.repositionTrafficLights(in: w)
            Self.hideTitlebarDecorationView(in: w)
            Self.neutralizeSafeAreaInsets(in: w)
            context.coordinator.observe(window: w)
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let w = nsView.window else { return }
        Self.applyWindowBackground(
            w,
            interfaceModeRaw: interfaceModeRaw,
            sidebarTransparencyEnabled: sidebarTransparencyEnabled
        )
    }

    private static func applyWindowBackground(
        _ window: NSWindow,
        interfaceModeRaw: String,
        sidebarTransparencyEnabled: Bool
    ) {
        let mode = AppearanceModeResolver.effectiveModeForWindow(
            modeRaw: interfaceModeRaw,
            legacyTransparencyEnabled: sidebarTransparencyEnabled
        )
        if mode.usesTransparentWindow {
            window.isOpaque = false
            window.backgroundColor = .clear
            return
        }
        window.isOpaque = true
        window.backgroundColor = KajiTheme.nsBg
    }

    static func neutralizeSafeAreaInsets(in window: NSWindow) {
        if #available(macOS 26.0, *) {
            guard let contentView = window.contentView else { return }
            contentView.additionalSafeAreaInsets.top = 0
            let baseSafeAreaTop = contentView.safeAreaInsets.top
            contentView.additionalSafeAreaInsets.top = -baseSafeAreaTop
        }
    }

    static func hideTitlebarDecorationView(in window: NSWindow) {
        guard let themeFrame = window.contentView?.superview else { return }
        for view in themeFrame.subviews {
            let name = NSStringFromClass(type(of: view))
            guard name.contains("NSTitlebarContainerView") else { continue }

            view.wantsLayer = true
            view.layer?.backgroundColor = CGColor.clear
            view.layer?.isOpaque = false

            for child in view.subviews {
                let childName = NSStringFromClass(type(of: child))
                if childName.contains("NSTitlebarDecorationView") {
                    child.isHidden = true
                }
                if childName.contains("NSTitlebarView") {
                    child.wantsLayer = true
                    child.layer?.backgroundColor = CGColor.clear
                    child.layer?.isOpaque = false
                    for sub in child.subviews {
                        let subName = NSStringFromClass(type(of: sub))
                        if subName == "NSView" || subName.contains("Background") {
                            sub.isHidden = true
                        }
                    }
                }
            }
        }
    }

    static func repositionTrafficLights(in window: NSWindow) {
        let isTahoe = if #available(macOS 26.0, *) { true } else { false }
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let btn = window.standardWindowButton(button) else { continue }
            btn.frame = WindowTrafficLightLayout.frame(for: button, currentFrame: btn.frame, isTahoe: isTahoe)
            btn.alphaValue = isTahoe ? 0.86 : 1
        }
    }

    final class Coordinator: NSObject {
        private var observations: [NSObjectProtocol] = []

        func observe(window: NSWindow) {
            guard observations.isEmpty else { return }

            let names: [Notification.Name] = [
                NSWindow.didResizeNotification,
                NSWindow.didEndLiveResizeNotification,
                NSWindow.didChangeScreenNotification,
                NSWindow.didChangeBackingPropertiesNotification,
                NSWindow.didExitFullScreenNotification,
                NSWindow.didEnterFullScreenNotification,
            ]
            for name in names {
                let token = NotificationCenter.default.addObserver(
                    forName: name,
                    object: window,
                    queue: .main
                ) { notification in
                    guard let w = notification.object as? NSWindow else { return }
                    MainActor.assumeIsolated {
                        WindowConfigurator.repositionTrafficLights(in: w)
                        WindowConfigurator.hideTitlebarDecorationView(in: w)
                        if name == NSWindow.didChangeScreenNotification
                            || name == NSWindow.didChangeBackingPropertiesNotification
                        {
                            WindowConfigurator.neutralizeSafeAreaInsets(in: w)
                        }
                        if name == NSWindow.didEnterFullScreenNotification
                            || name == NSWindow.didExitFullScreenNotification
                        {
                            WindowConfigurator.neutralizeSafeAreaInsets(in: w)
                            let isFullScreen = w.styleMask.contains(.fullScreen)
                            NotificationCenter.default.post(
                                name: .windowFullScreenDidChange,
                                object: nil,
                                userInfo: ["isFullScreen": isFullScreen]
                            )
                        }
                    }
                }
                observations.append(token)
            }
        }

        deinit {
            observations.forEach { NotificationCenter.default.removeObserver($0) }
        }
    }
}
