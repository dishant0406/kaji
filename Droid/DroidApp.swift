import AppKit
import SwiftUI

@main
struct DroidApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState: AppState
    @State private var projectStore: ProjectStore
    @State private var worktreeStore: WorktreeStore
    private let updateService = UpdateService.shared

    init() {
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
    }

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environment(appState)
                .environment(projectStore)
                .environment(worktreeStore)
                .environment(GhosttyService.shared)
                .environment(DroidConfig.shared)
                .environment(ThemeService.shared)
                .environment(AppTypographySettings.shared)
                .preferredColorScheme(DroidTheme.colorScheme)
                .onAppear {
                    NotificationStore.shared.appState = appState
                    NotificationStore.shared.worktreeStore = worktreeStore
                    NotificationStore.shared.markAllAsRead()
                    appDelegate.onTerminate = { [appState] in
                        appState.saveWorkspaces()
                    }
                    appDelegate.hasUnsavedEditorTabs = { [appState] in
                        appState.unsavedEditorTabs()
                    }
                    appState.onProjectsEmptied = { [projectStore, worktreeStore] projectIDs in
                        for id in projectIDs {
                            if let project = projectStore.projects.first(where: { $0.id == id }) {
                                let knownWorktrees = worktreeStore.list(for: id)
                                Task.detached {
                                    await WorktreeStore.cleanupOnDisk(
                                        for: project,
                                        knownWorktrees: knownWorktrees
                                    )
                                }
                            }
                            projectStore.remove(id: id)
                            worktreeStore.removeProject(id)
                        }
                    }
                }
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        .defaultSize(width: 1200, height: 800)
        .commands {
            DroidCommands(
                appState: appState,
                projectStore: projectStore,
                worktreeStore: worktreeStore,
                keyBindings: .shared,
                config: .shared,
                ghostty: .shared,
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
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        HugeIconFont.registerIfNeeded()
        setAppIcon()
        _ = GhosttyService.shared
        _ = AppTypographySettings.shared
        ThemeService.shared.applyDefaultThemeIfNeeded()
        UpdateService.shared.start()
        ModifierKeyMonitor.shared.start()
        ProviderEventReceiver.shared.start()
        CodexSessionMonitor.shared.start()
        SystemWakeCoordinator.shared.start()
        _ = CLILauncherSettings.shared
        AIProviderRegistry.shared.installAll()
        _ = AIUsageSettingsStore.isUsageEnabled()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let unsaved = hasUnsavedEditorTabs?() ?? []
        guard !unsaved.isEmpty else { return .terminateNow }

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
                if failures.isEmpty {
                    NSApp.reply(toApplicationShouldTerminate: true)
                    return
                }
                Self.presentSaveFailureAlert(failures: failures)
                NSApp.reply(toApplicationShouldTerminate: false)
            }
            return .terminateLater
        case .alertThirdButtonReturn:
            return .terminateNow
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

    func applicationWillTerminate(_ notification: Notification) {
        onTerminate?()
        NotificationStore.shared.saveToDisk()
        SystemWakeCoordinator.shared.stop()
        CodexSessionMonitor.shared.stop()
        ProviderEventReceiver.shared.stop()
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
            Self.applyWindowBackground(w, sidebarTransparencyEnabled: sidebarTransparencyEnabled)
            Self.repositionTrafficLights(in: w)
            Self.hideTitlebarDecorationView(in: w)
            Self.neutralizeSafeAreaInsets(in: w)
            context.coordinator.observe(window: w)
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let w = nsView.window else { return }
        Self.applyWindowBackground(w, sidebarTransparencyEnabled: sidebarTransparencyEnabled)
    }

    private static func applyWindowBackground(_ window: NSWindow, sidebarTransparencyEnabled: Bool) {
        if sidebarTransparencyEnabled, !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            window.isOpaque = false
            window.backgroundColor = .clear
            return
        }
        window.isOpaque = true
        window.backgroundColor = DroidTheme.nsBg
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

            // Make the container itself transparent
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

    static let trafficLightY: CGFloat = 3.5

    static func repositionTrafficLights(in window: NSWindow) {
        let y: CGFloat
        if #available(macOS 26.0, *) {
            // On macOS 26, center traffic lights vertically in the 32px title bar
            let buttonHeight: CGFloat = 14
            y = (32 - buttonHeight) / 2
        } else {
            y = trafficLightY
        }
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let btn = window.standardWindowButton(button) else { continue }
            var frame = btn.frame
            frame.origin.y = y
            btn.frame = frame
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
