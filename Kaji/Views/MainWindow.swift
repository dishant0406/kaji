import AppKit
import SwiftUI

struct MainWindow: View {
    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore
    @Environment(WorktreeStore.self) private var worktreeStore
    @Environment(GhosttyService.self) private var ghostty
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragCoordinator = TabDragCoordinator()
    @State private var paneDragCoordinator = PaneDragCoordinator()
    private enum AttachedVCSLayout {
        static let minWidth: CGFloat = 200
        static let defaultWidth: CGFloat = 400
        static let maxWidth: CGFloat = 800
    }

    private enum FileTreeLayout {
        static let minWidth: CGFloat = 180
        static let defaultWidth: CGFloat = 260
        static let maxWidth: CGFloat = 600
    }

    private enum AgentInstructionsLayout {
        static let minWidth: CGFloat = 360
        static let widthRatio: CGFloat = 0.5
    }

    private enum CodeGraphAgentLayout {
        static let minWidth: CGFloat = 360
        static let defaultWidth: CGFloat = 460
        static let maxWidth: CGFloat = 760
    }

    private enum BrowserLayout {
        static let minWidth: CGFloat = 420
        static let defaultWidth: CGFloat = 560
        static let maxWidth: CGFloat = 980
        static let resizeHandleWidth: CGFloat = 28
        static let maxRetainedSessions = 3
    }

    private enum SidePanelIdentity: Hashable {
        case codeGraphAgent(UUID)
        case vcs
        case problems
        case globalSearch(UUID)
        case fileTree(WorktreeKey)
        case agentInstructions(UUID)
        case browser(WorktreeKey)
    }

    private enum CloseConfirmationKind {
        case lastTab
        case unsavedEditor
        case runningProcess

        var title: String {
            switch self {
            case .lastTab:
                "Close Project?"
            case .unsavedEditor:
                "Save Changes Before Closing?"
            case .runningProcess:
                "Close Tab?"
            }
        }

        var message: String {
            switch self {
            case .lastTab:
                "This is the last tab. Closing it will remove the project from the sidebar."
            case .unsavedEditor:
                "This file has unsaved changes. If you don't save, your changes will be lost."
            case .runningProcess:
                "A process is still running in this tab. Are you sure you want to close it?"
            }
        }
    }

    private struct ProjectLogoCropRequest: Identifiable {
        let id = UUID()
        let projectID: UUID
        let image: NSImage
    }

    @State private var vcsPanelVisible = false
    @State private var vcsPanelWidth: CGFloat = AttachedVCSLayout.defaultWidth
    @State private var vcsStates: [WorktreeKey: VCSTabState] = [:]
    @State private var fileTreePanelVisible = false
    @State private var globalSearchPanelVisible = false
    @State private var problemsPanelVisible = false
    @AppStorage("kaji.fileTreeWidth") private var fileTreePanelWidth: Double = .init(FileTreeLayout.defaultWidth)
    @AppStorage("kaji.codeGraphAgentPanelWidth") private var codeGraphAgentPanelWidth: Double = .init(CodeGraphAgentLayout.defaultWidth)
    @State private var fileTreeStates: [WorktreeKey: FileTreeState] = [:]
    @State private var browserPanelVisible = false
    @State private var browserPanelKey: WorktreeKey?
    @AppStorage(BrowserExtensionPreferences.enabledKey) private var browserEnabled = false
    @AppStorage("kaji.browserPanelWidth") private var browserPanelWidth: Double = .init(BrowserLayout.defaultWidth)
    @State private var browserSessions: [WorktreeKey: BrowserSession] = [:]
    @State private var agentInstructionPanelVisible = false
    @State private var agentInstructionState = AgentInstructionPanelState()
    @State private var codeGraphAgentCoordinator = KajiCodeGraphAgentCoordinator.shared
    @State private var cliLauncherSettings = CLILauncherSettings.shared
    @State private var footerTerminalStore = FooterTerminalStateStore()
    @State private var footerTerminalCleanupTasks: [UUID: Task<Void, Never>] = [:]
    @State private var showCommandPalette = false
    @State private var showQuickOpen = false
    @State private var showAsk = false
    @State private var showAgentCommandCenter = false
    @State private var showWorktreeSwitcher = false
    @State private var showGoToSymbol = false
    @State private var showGoToLine = false
    @State private var showSettings = false
    @State private var showMCPControlPanel = false
    @State private var showCreateThemeModal = false
    @State private var parentAgentSettings = ParentAgentSettingsStore.shared
    @State private var createWorktreeProjectID: UUID?
    @State private var projectLogoCropRequest: ProjectLogoCropRequest?
    @AppStorage(AppearanceSettingsKeys.sidebarTransparencyEnabled) private var sidebarTransparencyEnabled = false
    @AppStorage(AppearanceSettingsKeys.interfaceTransparencyAmount) private var interfaceTransparencyAmount = 0.7
    @AppStorage("kaji.notifications.toastPosition") private var toastPositionRaw = ToastPosition.topCenter.rawValue
    @AppStorage(GeneralSettingsKeys.footerTerminalEnabled) private var footerTerminalEnabled = true

    var body: some View {
        configuredMainLayout
    }

    private var configuredMainLayout: AnyView {
        let overlayed = AnyView(
            mainLayout
                .environment(\.overlayActive, overlayActive)
                .overlay(alignment: toastAlignment) { toastOverlay }
                .overlay { commandPaletteOverlay }
                .overlay { quickOpenOverlay }
                .overlay { askOverlay }
                .overlay { agentCommandCenterOverlay }
                .overlay { worktreeSwitcherOverlay }
                .overlay { goToSymbolOverlay }
                .overlay { goToLineOverlay }
        )

        let base = AnyView(
            overlayed
                .overlay { settingsOverlay }
                .overlay { mcpControlPanelOverlay }
                .overlay { createWorktreeOverlay }
                .overlay { createThemeOverlay }
                .overlay { projectLogoCropperOverlay }
                .animation(KajiMotion.preferred(KajiMotion.modal, reduceMotion: reduceMotion), value: showSettings)
                .animation(KajiMotion.preferred(KajiMotion.modal, reduceMotion: reduceMotion), value: showMCPControlPanel)
                .animation(KajiMotion.preferred(KajiMotion.modal, reduceMotion: reduceMotion), value: showCreateThemeModal)
                .animation(KajiMotion.preferred(KajiMotion.modal, reduceMotion: reduceMotion), value: createWorktreeProjectID)
                .animation(KajiMotion.preferred(KajiMotion.modal, reduceMotion: reduceMotion), value: projectLogoCropRequest?.id)
                .animation(KajiMotion.preferred(KajiMotion.fast, reduceMotion: reduceMotion), value: ToastState.shared.message != nil)
                .task(id: activeQuickOpenProjectPath) {
                    guard let path = activeQuickOpenProjectPath else { return }
                    await FileSearchService.warm(projectPath: path)
                }
                .coordinateSpace(name: DragCoordinateSpace.mainWindow)
                .environment(dragCoordinator)
                .environment(paneDragCoordinator)
                .background(MainWindowShortcutInterceptor(
                    onShortcut: { action in handleShortcutAction(action) },
                    onMouseBack: { appState.goBack() },
                    onMouseForward: { appState.goForward() }
                ))
                .background(
                    WindowConfigurator(
                        configVersion: ghostty.configVersion,
                        sidebarTransparencyEnabled: sidebarTransparencyEnabled
                    )
                )
                .background(WindowTitleUpdater(title: windowTitle))
                .ignoresSafeArea(.container, edges: .top)
                .modifier(FileTreeSelectionSync(
                    filePath: activeEditorFilePath,
                    panelVisible: fileTreePanelVisible,
                    sync: syncFileTreeSelection
                ))
        )

        let receives1 = AnyView(
            base
                .onReceive(NotificationCenter.default.publisher(for: .commandPalette)) { _ in
                    showQuickOpen = false
                    showAsk = false
                    showAgentCommandCenter = false
                    showWorktreeSwitcher = false
                    showGoToSymbol = false
                    showGoToLine = false
                    showCommandPalette.toggle()
                }
                .onReceive(NotificationCenter.default.publisher(for: .quickOpen)) { _ in
                    showCommandPalette = false
                    showQuickOpen.toggle()
                }
                .onReceive(NotificationCenter.default.publisher(for: .goToSymbol)) { _ in
                    showQuickOpen = false
                    showAsk = false
                    showAgentCommandCenter = false
                    showWorktreeSwitcher = false
                    showCommandPalette = false
                    showGoToLine = false
                    showGoToSymbol.toggle()
                }
                .onReceive(NotificationCenter.default.publisher(for: .goToLine)) { _ in
                    showQuickOpen = false
                    showAsk = false
                    showAgentCommandCenter = false
                    showWorktreeSwitcher = false
                    showCommandPalette = false
                    showGoToSymbol = false
                    showGoToLine.toggle()
                }
                .onReceive(NotificationCenter.default.publisher(for: .ask)) { _ in
                    let shouldShow = !showAsk
                    showCommandPalette = false
                    showQuickOpen = false
                    showAgentCommandCenter = false
                    showWorktreeSwitcher = false
                    showGoToSymbol = false
                    showGoToLine = false
                    showAsk = shouldShow
                }
                .onReceive(NotificationCenter.default.publisher(for: .openAskWithPrefill)) { _ in
                    showCommandPalette = false
                    showQuickOpen = false
                    showAgentCommandCenter = false
                    showWorktreeSwitcher = false
                    showGoToSymbol = false
                    showGoToLine = false
                    showAsk = true
                }
                .onReceive(NotificationCenter.default.publisher(for: .agentCommandCenter)) { _ in
                    let shouldShow = !showAgentCommandCenter
                    showCommandPalette = false
                    showQuickOpen = false
                    showAsk = false
                    showWorktreeSwitcher = false
                    showGoToSymbol = false
                    showGoToLine = false
                    showAgentCommandCenter = shouldShow
                }
                .onReceive(NotificationCenter.default.publisher(for: .showParentAgentHome)) { _ in
                    guard parentAgentSettings.isEnabled else {
                        showSettings = true
                        return
                    }
                    showCommandPalette = false
                    showQuickOpen = false
                    showAsk = false
                    showAgentCommandCenter = false
                    showWorktreeSwitcher = false
                    showGoToSymbol = false
                    showGoToLine = false
                    appState.showParentAgentHome()
                }
                .onReceive(NotificationCenter.default.publisher(for: .hideParentAgentHome)) { _ in
                    appState.hideParentAgentHome()
                }
                .onReceive(NotificationCenter.default.publisher(for: .switchWorktree)) { _ in
                    showCommandPalette = false
                    showWorktreeSwitcher.toggle()
                }
                .onReceive(NotificationCenter.default.publisher(for: .toggleSettings)) { _ in
                    showCommandPalette = false
                    showQuickOpen = false
                    showAsk = false
                    showAgentCommandCenter = false
                    showWorktreeSwitcher = false
                    showSettings.toggle()
                }
                .onReceive(NotificationCenter.default.publisher(for: .openParentAgentSettings)) { _ in
                    showQuickOpen = false
                    showAsk = false
                    showAgentCommandCenter = false
                    showWorktreeSwitcher = false
                    showSettings = true
                }
                .onReceive(NotificationCenter.default.publisher(for: .requestCreateWorktreeModal)) { notification in
                    guard let projectID = notification.userInfo?["projectID"] as? UUID else { return }
                    requestCreateWorktree(projectID: projectID)
                }
                .onReceive(NotificationCenter.default.publisher(for: .requestCreateThemeModal)) { _ in
                    showCreateThemeModal = true
                }
                .onReceive(NotificationCenter.default.publisher(for: .requestProjectLogoCropper)) { notification in
                    guard let projectID = notification.userInfo?["projectID"] as? UUID,
                          let image = notification.userInfo?["image"] as? NSImage
                    else { return }
                    projectLogoCropRequest = ProjectLogoCropRequest(projectID: projectID, image: image)
                }
        )

        let receives2 = AnyView(
            receives1
                .onReceive(NotificationCenter.default.publisher(for: .dismissSettings)) { _ in
                    showSettings = false
                }
        )

        let receives3 = AnyView(
            receives2
                .onReceive(NotificationCenter.default.publisher(for: .toggleAttachedVCS)) { _ in
                    toggleAttachedVCSPanel()
                }
                .onReceive(NotificationCenter.default.publisher(for: .toggleFileTree)) { _ in
                    toggleFileTreePanel()
                }
                .onReceive(NotificationCenter.default.publisher(for: .toggleGlobalSearch)) { _ in
                    toggleGlobalSearchPanel()
                }
                .onReceive(NotificationCenter.default.publisher(for: .toggleProblemsPanel)) { _ in
                    toggleProblemsPanel()
                }
                .onReceive(NotificationCenter.default.publisher(for: .toggleBrowserPanel)) { _ in
                    guard browserEnabled else { return }
                    toggleBrowserPanel()
                }
                .onReceive(NotificationCenter.default.publisher(for: .openBrowserPanel)) { _ in
                    guard browserEnabled else { return }
                    showBrowserPanel()
                }
                .onReceive(NotificationCenter.default.publisher(for: .closeBrowserPanel)) { _ in
                    hideBrowserPanel()
                }
                .onReceive(NotificationCenter.default.publisher(for: .toggleFooterTerminal)) { _ in
                    guard footerTerminalEnabled else { return }
                    toggleFooterTerminal()
                }
        )

        let changes1 = AnyView(
            receives3
                .onChange(of: vcsPruneSignature) {
                    pruneVCSStates()
                    pruneFileTreeStates()
                    pruneBrowserStates()
                }
                .onChange(of: vcsEnsureSignature) {
                    guard let project = activeProject else { return }
                    if vcsPanelVisible {
                        ensureVCSState(for: project)
                    }
                    if fileTreePanelVisible {
                        ensureFileTreeState(for: project)
                    }
                    if isBrowserPanelVisibleForActiveWorktree {
                        ensureBrowserState(for: project)
                    }
                }
                .onChange(of: appState.pendingLastTabClose != nil) { _, isPresented in
                    guard isPresented else { return }
                    presentCloseConfirmation(.lastTab)
                }
        )

        return AnyView(
            changes1
                .onChange(of: appState.pendingUnsavedEditorTabClose != nil) { _, isPresented in
                    guard isPresented else { return }
                    presentCloseConfirmation(.unsavedEditor)
                }
                .onChange(of: appState.pendingProcessTabClose != nil) { _, isPresented in
                    guard isPresented else { return }
                    presentCloseConfirmation(.runningProcess)
                }
                .onChange(of: appState.pendingSaveErrorMessage != nil) { _, isPresented in
                    guard isPresented, let message = appState.pendingSaveErrorMessage else { return }
                    presentSaveErrorAlert(message: message)
                }
                .onChange(of: appState.pendingLanguagePackInstall != nil) { _, isPresented in
                    guard isPresented else { return }
                    presentLanguagePackInstallToast()
                }
                .onChange(of: appState.pendingLanguagePackInstallErrorMessage != nil) { _, isPresented in
                    guard isPresented, let message = appState.pendingLanguagePackInstallErrorMessage else { return }
                    ToastState.shared.show("Language pack install failed: \(message)")
                    appState.pendingLanguagePackInstallErrorMessage = nil
                }
                .onChange(of: footerTerminalEnabled) { _, enabled in
                    if !enabled {
                        collapseAllFooterTerminals()
                    }
                }
                .onChange(of: browserEnabled) { _, enabled in
                    if !enabled {
                        closeBrowserFeature()
                    }
                }
        )
    }

    private var overlayActive: Bool {
        showCommandPalette || showQuickOpen || showAsk || showAgentCommandCenter || showWorktreeSwitcher || showGoToSymbol ||
            showGoToLine ||
            showSettings || showMCPControlPanel ||
            showCreateThemeModal || createWorktreeProjectID != nil || projectLogoCropRequest != nil
    }

    private var activeSidePanelIdentity: SidePanelIdentity? {
        if let session = activeCodeGraphAgentSession { return .codeGraphAgent(session.id) }
        if vcsPanelVisible, activeVCSState != nil { return .vcs }
        if problemsPanelVisible { return .problems }
        if globalSearchPanelVisible, let project = activeProject { return .globalSearch(project.id) }
        if fileTreePanelVisible, let key = activeWorktreeKey, activeFileTreeState != nil { return .fileTree(key) }
        if agentInstructionPanelVisible, let project = activeProject { return .agentInstructions(project.id) }
        if browserEnabled, isBrowserPanelVisibleForActiveWorktree, let key = activeWorktreeKey, activeBrowserState != nil { return .browser(key) }
        return nil
    }

    private var mainLayout: some View {
        VStack(spacing: 0) {
            topBarContent
                .frame(height: 38)
                .background(WindowDragRepresentable())
                .background(
                    ChromeBackgroundSurface(
                        transparencyEnabled: sidebarTransparencyEnabled,
                        transparencyAmount: interfaceTransparencyAmount
                    )
                )

            Rectangle().fill(KajiTheme.border).frame(height: 1)
                .background(
                    ChromeBackgroundSurface(
                        transparencyEnabled: sidebarTransparencyEnabled,
                        transparencyAmount: interfaceTransparencyAmount
                    )
                )

            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    Sidebar(
                        parentAgentSelected: parentAgentSelected,
                        parentAgentEnabled: parentAgentSettings.isEnabled
                    )
                    Rectangle().fill(KajiTheme.border).frame(width: 1)
                        .accessibilityHidden(true)
                }
                .fixedSize(horizontal: true, vertical: false)
                .background(
                    SidebarBackgroundSurface(
                        transparencyEnabled: sidebarTransparencyEnabled,
                        transparencyAmount: interfaceTransparencyAmount
                    )
                )

                VStack(spacing: 0) {
                    if showsWorkspaceTabBar {
                        workspaceTabBarContent
                            .frame(height: 36)
                            .background(
                                ChromeBackgroundSurface(
                                    transparencyEnabled: sidebarTransparencyEnabled,
                                    transparencyAmount: interfaceTransparencyAmount
                                )
                            )

                        Rectangle().fill(KajiTheme.border).frame(height: 1)
                            .background(
                                ChromeBackgroundSurface(
                                    transparencyEnabled: sidebarTransparencyEnabled,
                                    transparencyAmount: interfaceTransparencyAmount
                                )
                            )
                    }

                    GeometryReader { contentGeometry in
                        HStack(spacing: 0) {
                            ZStack {
                                KajiTheme.bg
                                workspaceContent
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                            activeSidePanel(contentWidth: contentGeometry.size.width)
                                .id(activeSidePanelIdentity)
                                .transition(KajiMotion.sidePanelTransition(reduceMotion: reduceMotion))
                        }
                        .animation(KajiMotion.preferred(KajiMotion.panel, reduceMotion: reduceMotion), value: activeSidePanelIdentity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    footerTerminalOverlay
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private var workspaceContent: some View {
        if appState.isParentAgentHomePresented {
            ParentAgentTabContent()
        } else if let project = activeProject,
                  appState.workspaceRoot(for: project.id) == nil,
                  resolvedActiveWorktree(for: project) != nil
        {
            EmptyProjectPlaceholder(project: project) {
                activateWorkspace()
                appState.createTab(projectID: project.id)
            }
        } else if projectsWithWorkspaces.isEmpty {
            WelcomeView()
        } else if let project = activeProjectWithWorkspace,
                  let activeKey = appState.activeWorktreeKey(for: project.id)
        {
            ForEach(mountedWorktreeKeys(for: project), id: \.self) { key in
                TerminalArea(
                    project: project,
                    worktreeKey: key,
                    isActiveProject: key == activeKey
                )
                .opacity(key == activeKey ? 1 : 0)
                .allowsHitTesting(key == activeKey)
                .zIndex(key == activeKey ? 1 : 0)
            }
        }
    }

    @ViewBuilder
    private func activeSidePanel(contentWidth: CGFloat) -> some View {
        if let session = activeCodeGraphAgentSession {
            codeGraphAgentSidePanel(session: session)
        } else if vcsPanelVisible, let state = activeVCSState {
            HStack(spacing: 0) {
                sidePanelResizeHandle { delta in
                    vcsPanelWidth = max(
                        AttachedVCSLayout.minWidth,
                        min(AttachedVCSLayout.maxWidth, vcsPanelWidth - delta)
                    )
                }
                VCSTabView(state: state, focused: false, onFocus: {})
                    .frame(width: vcsPanelWidth)
            }
        } else if problemsPanelVisible {
            problemsSidePanel()
        } else if globalSearchPanelVisible, let project = activeProject {
            globalSearchSidePanel(project: project)
        } else if fileTreePanelVisible, let treeState = activeFileTreeState {
            fileTreeSidePanel(treeState: treeState)
        } else if agentInstructionPanelVisible, let project = activeProject {
            HStack(spacing: 0) {
                Rectangle().fill(KajiTheme.border).frame(width: 1)
                AgentInstructionsPanel(
                    state: agentInstructionState,
                    projectPath: activeWorktreePath(for: project),
                    enabledLaunchers: cliLauncherSettings.enabledLaunchers,
                    onClose: { withSidePanelAnimation { agentInstructionPanelVisible = false } }
                )
                .frame(width: max(AgentInstructionsLayout.minWidth, contentWidth * AgentInstructionsLayout.widthRatio))
            }
        } else if browserEnabled, isBrowserPanelVisibleForActiveWorktree, let state = activeBrowserState, let key = activeWorktreeKey {
            browserSidePanel(state: state, sessionID: key.worktreeID.uuidString)
        }
    }

    private func codeGraphAgentSidePanel(session: KajiCodeGraphAgentSession) -> some View {
        HStack(spacing: 0) {
            sidePanelResizeHandle { delta in
                let next = codeGraphAgentPanelWidth - Double(delta)
                codeGraphAgentPanelWidth = max(
                    Double(CodeGraphAgentLayout.minWidth),
                    min(Double(CodeGraphAgentLayout.maxWidth), next)
                )
            }
            KajiCodeGraphAgentPanel(
                session: session,
                onHide: {
                    guard let key = activeWorktreeKey else { return }
                    codeGraphAgentCoordinator.hide(projectID: key.projectID, worktreeID: key.worktreeID)
                },
                onClose: {
                    codeGraphAgentCoordinator.close(session)
                }
            )
            .frame(width: CGFloat(codeGraphAgentPanelWidth))
        }
    }

    private func browserSidePanel(state: BrowserPaneState, sessionID: String) -> some View {
        HStack(spacing: 0) {
            sidePanelResizeHandle { delta in
                let next = browserPanelWidth - Double(delta)
                browserPanelWidth = max(
                    Double(BrowserLayout.minWidth),
                    min(Double(BrowserLayout.maxWidth), next)
                )
            }
            BrowserPane(
                state: state,
                sessionID: sessionID,
                closeOnDisappear: false,
                managesBrowserControl: false,
                paneIsVisible: true,
                onClosePane: { hideBrowserPanel() }
            )
            .frame(width: CGFloat(browserPanelWidth))
            .clipped()
        }
    }

    private func fileTreeSidePanel(treeState: FileTreeState) -> some View {
        HStack(spacing: 0) {
            sidePanelResizeHandle { delta in
                let next = fileTreePanelWidth - Double(delta)
                fileTreePanelWidth = max(Double(FileTreeLayout.minWidth), min(Double(FileTreeLayout.maxWidth), next))
            }
            FileTreeView(
                state: treeState,
                onOpenFile: { filePath in
                    activateWorkspace()
                    guard let projectID = appState.activeProjectID else { return }
                    appState.openFile(filePath, projectID: projectID)
                },
                onOpenTerminal: { directory in
                    activateWorkspace()
                    guard let projectID = appState.activeProjectID else { return }
                    appState.dispatch(.createTabInDirectory(projectID: projectID, areaID: nil, directory: directory))
                },
                onFileMoved: { oldPath, newPath in
                    appState.handleFileMoved(from: oldPath, to: newPath)
                }
            )
            .id(treeState.rootPath)
            .frame(width: CGFloat(fileTreePanelWidth))
        }
    }

    private func globalSearchSidePanel(project: Project) -> some View {
        HStack(spacing: 0) {
            sidePanelResizeHandle { delta in
                let next = fileTreePanelWidth - Double(delta)
                fileTreePanelWidth = max(Double(FileTreeLayout.minWidth), min(Double(FileTreeLayout.maxWidth), next))
            }
            GlobalSearchPanel(
                projectPath: activeWorktreePath(for: project),
                onOpenMatch: { match in
                    activateWorkspace()
                    appState.openFile(match.filePath, projectID: project.id)
                    activeEditorState?.navigate(to: .init(line: match.line, column: match.column))
                },
                onReplaceComplete: { changedPaths in
                    appState.reloadOpenEditors(paths: Set(changedPaths))
                },
                onClose: { withSidePanelAnimation { globalSearchPanelVisible = false } }
            )
            .frame(width: CGFloat(fileTreePanelWidth))
        }
    }

    private func problemsSidePanel() -> some View {
        HStack(spacing: 0) {
            sidePanelResizeHandle { delta in
                let next = fileTreePanelWidth - Double(delta)
                fileTreePanelWidth = max(Double(FileTreeLayout.minWidth), min(Double(FileTreeLayout.maxWidth), next))
            }
            ProblemsPanel(
                store: DiagnosticsStore.shared,
                onOpenDiagnostic: { diagnostic in
                    guard let project = activeProject else { return }
                    activateWorkspace()
                    appState.openFile(diagnostic.filePath, projectID: project.id)
                    activeEditorState?.navigate(to: .init(line: diagnostic.line, column: diagnostic.column))
                },
                onClose: { withSidePanelAnimation { problemsPanelVisible = false } }
            )
            .frame(width: CGFloat(fileTreePanelWidth))
        }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast = ToastState.shared.message {
            HStack(spacing: 6) {
                KajiIcon(systemName: "checkmark.circle.fill", size: 12)
                    .foregroundStyle(KajiTheme.diffAddFg)
                Text(toast)
                    .kajiFont(size: 12, weight: .medium)
                    .foregroundStyle(KajiTheme.fg)
                if let actionTitle = ToastState.shared.actionTitle {
                    Button(actionTitle) {
                        ToastState.shared.performAction()
                    }
                    .buttonStyle(.plain)
                    .kajiFont(size: 12, weight: .semibold)
                    .foregroundStyle(KajiTheme.accent)
                    Button {
                        ToastState.shared.dismissActionToast()
                    } label: {
                        KajiIcon(systemName: "xmark", size: 9)
                            .foregroundStyle(KajiTheme.fgMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(KajiTheme.surface, in: RoundedRectangle(cornerRadius: KajiShape.panelRadius))
            .overlay(
                RoundedRectangle(cornerRadius: KajiShape.panelRadius)
                    .stroke(KajiTheme.border, lineWidth: 1)
            )
            .padding(toastEdgePadding)
            .transition(.move(edge: toastTransitionEdge).combined(with: .opacity))
            .allowsHitTesting(ToastState.shared.actionTitle != nil)
            .accessibilityLabel(toast)
            .accessibilityAddTraits(.isStaticText)
        }
    }

    @ViewBuilder
    private var commandPaletteOverlay: some View {
        if showCommandPalette {
            CommandPaletteOverlay(
                onSelect: { command in
                    showCommandPalette = false
                    performCommand(command)
                },
                onDismiss: { showCommandPalette = false }
            )
        }
    }

    @ViewBuilder
    private var quickOpenOverlay: some View {
        if showQuickOpen, let project = activeProject {
            QuickOpenOverlay(
                projectPath: activeWorktreePath(for: project),
                onSelect: { filePath in
                    activateWorkspace()
                    showQuickOpen = false
                    appState.openFile(filePath, projectID: project.id)
                },
                onDismiss: { showQuickOpen = false }
            )
        }
    }

    @ViewBuilder
    private var askOverlay: some View {
        if showAsk {
            AskOverlay(
                onDismiss: { showAsk = false }
            )
        }
    }

    @ViewBuilder
    private var agentCommandCenterOverlay: some View {
        if showAgentCommandCenter {
            AgentCommandCenterOverlay(
                onDismiss: { showAgentCommandCenter = false }
            )
        }
    }

    @ViewBuilder
    private var worktreeSwitcherOverlay: some View {
        if showWorktreeSwitcher {
            WorktreeSwitcherOverlay(
                items: worktreeSwitcherItems,
                activeKey: activeWorktreeKey,
                onSelect: { item in
                    activateWorkspace()
                    showWorktreeSwitcher = false
                    guard let project = projectStore.projects.first(where: { $0.id == item.projectID }) else { return }
                    if appState.activeProjectID == item.projectID {
                        appState.selectWorktree(projectID: item.projectID, worktree: item.worktree)
                    } else {
                        appState.selectProject(project, worktree: item.worktree)
                    }
                },
                onDismiss: { showWorktreeSwitcher = false }
            )
        }
    }

    @ViewBuilder
    private var goToSymbolOverlay: some View {
        if showGoToSymbol, let editor = activeEditorState {
            GoToSymbolOverlay(
                symbols: editor.symbols(),
                onSelect: { symbol in
                    editor.navigate(to: symbol)
                    showGoToSymbol = false
                },
                onDismiss: { showGoToSymbol = false }
            )
        }
    }

    @ViewBuilder
    private var goToLineOverlay: some View {
        if showGoToLine, let editor = activeEditorState {
            GoToLineOverlay(
                currentLine: editor.cursorLine,
                maxLine: max(1, editor.backingStore?.lineCount ?? 1),
                onSelect: { request in
                    editor.navigate(to: request)
                    showGoToLine = false
                },
                onDismiss: { showGoToLine = false }
            )
        }
    }

    @ViewBuilder
    private var settingsOverlay: some View {
        if showSettings {
            ZStack {
                Color.black.opacity(0.12)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showSettings = false
                    }

                SettingsView {
                    showSettings = false
                }
                .padding(24)
                .transition(KajiMotion.modalTransition(reduceMotion: reduceMotion))
            }
        }
    }

    @ViewBuilder
    private var mcpControlPanelOverlay: some View {
        if showMCPControlPanel {
            KajiModalOverlay {
                showMCPControlPanel = false
            } content: {
                MCPServerControlPanel(projectPath: activeProject.map { activeWorktreePath(for: $0) }) {
                    showMCPControlPanel = false
                }
            }
        }
    }

    @ViewBuilder
    private var createWorktreeOverlay: some View {
        if let projectID = createWorktreeProjectID,
           let project = projectStore.projects.first(where: { $0.id == projectID })
        {
            KajiModalOverlay {
                createWorktreeProjectID = nil
            } content: {
                CreateWorktreeModal(project: project) { result in
                    createWorktreeProjectID = nil
                    handleCreateWorktreeResult(result, project: project)
                }
                .environment(worktreeStore)
            }
        }
    }

    @ViewBuilder
    private var createThemeOverlay: some View {
        if showCreateThemeModal {
            KajiModalOverlay {
                showCreateThemeModal = false
            } content: {
                CreateThemeModal {
                    showCreateThemeModal = false
                }
            }
        }
    }

    @ViewBuilder
    private var projectLogoCropperOverlay: some View {
        if let request = projectLogoCropRequest {
            KajiModalOverlay {
                projectLogoCropRequest = nil
            } content: {
                LogoCropperSheet(
                    sourceImage: request.image,
                    onConfirm: { cropped in
                        let logoPath = ProjectLogoStorage.save(
                            croppedImage: cropped,
                            forProjectID: request.projectID
                        )
                        projectStore.setLogo(id: request.projectID, to: logoPath)
                        projectLogoCropRequest = nil
                    },
                    onCancel: { projectLogoCropRequest = nil }
                )
            }
        }
    }

    private var topBarContent: some View {
        WindowDragRepresentable(alwaysEnabled: true)
            .overlay(alignment: .leading) {
                HStack(spacing: 8) {
                    ResourceMonitorTopBarButton()
                    PortMonitorTopBarButton()
                    TopBarSearchButton(
                        title: topBarSearchTitle,
                        shortcut: KeyBindingStore.shared.combo(for: .quickOpen).displayString,
                        enabled: activeProjectWithWorkspace != nil
                    ) {
                        NotificationCenter.default.post(name: .quickOpen, object: nil)
                    }
                    CodingAgentProcessTopBarButton()
                    AIUsageTopBarButton()
                }
                .padding(.leading, 8)
            }
            .overlay(alignment: .trailing) {
                topBarActions
                    .padding(.trailing, 8)
            }
    }

    @ViewBuilder
    private var workspaceTabBarContent: some View {
        if let project = activeProject,
           let workspace = appState.workspace(for: project.id),
           let activeWorkspaceTab = workspace.activeTab,
           let areaID = activeWorkspaceTab.activeArea?.id
        {
            PaneTabStrip(
                areaID: areaID,
                tabs: PaneTabStrip.workspaceSnapshots(from: workspace.tabs),
                activeTabID: workspace.activeTabID,
                isFocused: true,
                isWindowTitleBar: false,
                allowsExternalDrops: false,
                showVCSButton: false,
                showSettingsButton: false,
                projectID: project.id,
                onSelectTab: { tabID in
                    activateWorkspace()
                    appState.dispatch(.selectTab(projectID: project.id, areaID: areaID, tabID: tabID))
                },
                onCreateTab: {
                    withSidePanelAnimation {
                        activateWorkspace()
                        appState.dispatch(.createTab(projectID: project.id, areaID: nil))
                    }
                },
                onCreateVCSTab: {
                    withSidePanelAnimation {
                        activateWorkspace()
                        openVCS(for: project, preferredAreaID: areaID)
                    }
                },
                onCloseTab: { tabID in
                    activateWorkspace()
                    appState.closeTab(tabID, areaID: areaID, projectID: project.id)
                },
                onSplit: { dir in
                    withSidePanelAnimation {
                        activateWorkspace()
                        appState.dispatch(.splitArea(.init(
                            projectID: project.id,
                            areaID: areaID,
                            direction: dir,
                            position: .second
                        )))
                    }
                },
                onDropAction: { result in
                    withSidePanelAnimation {
                        activateWorkspace()
                        appState.dispatch(result.action(projectID: project.id))
                    }
                },
                onCreateTabAdjacent: { tabID, side in
                    withSidePanelAnimation {
                        activateWorkspace()
                        let path = activeWorktreePath(for: project)
                        let area = TabArea(projectPath: path)
                        let tab = WorkspaceTab(root: .tabArea(area), focusedAreaID: area.id)
                        workspace.insertTab(
                            tab,
                            adjacentTo: tabID,
                            side: side
                        )
                        appState.dispatch(.selectTab(projectID: project.id, areaID: areaID, tabID: tab.id))
                        appState.saveWorkspaces()
                    }
                },
                onTogglePin: { tabID in
                    workspace.togglePin(tabID)
                    appState.saveWorkspaces()
                },
                onSetCustomTitle: { tabID, title in
                    workspace.tabs.first(where: { $0.id == tabID })?.customTitle = title
                    appState.saveWorkspaces()
                },
                onSetColorID: { tabID, colorID in
                    workspace.tabs.first(where: { $0.id == tabID })?.colorID = colorID
                    appState.saveWorkspaces()
                },
                onReorderTab: { fromOffsets, toOffset in
                    workspace.reorderTab(fromOffsets: fromOffsets, toOffset: toOffset)
                    appState.saveWorkspaces()
                }
            )
        }
    }

    private var topBarActions: some View {
        HStack(spacing: 0) {
            if let project = activeProject {
                TopBarBranchPicker()
                    .padding(.trailing, 4)
                FileDiffIconButton {
                    openVCS(for: project)
                }
                .help("Source Control (\(KeyBindingStore.shared.combo(for: .openVCSTab).displayString))")
                AgentInstructionsButton(selected: agentInstructionPanelVisible) {
                    toggleAgentInstructionPanel()
                }
                .help("Agent Instructions")
                FileTreeIconButton {
                    NotificationCenter.default.post(name: .toggleFileTree, object: nil)
                }
                .help("File Tree (\(KeyBindingStore.shared.combo(for: .toggleFileTree).displayString))")
            }
            IconButton(symbol: "gearshape", size: 12, accessibilityLabel: "Settings") {
                NotificationCenter.default.post(name: .toggleSettings, object: nil)
            }
            .help("Settings (⌘,)")
        }
    }

    @ViewBuilder
    private var footerTerminalOverlay: some View {
        if let project = activeProject {
            let isVisible = footerTerminalStore.isVisible(for: project.id)
            FooterTerminalOverlay(
                projectID: project.id,
                terminalState: footerTerminalStore.state(for: project.id),
                worktreeKey: activeWorktreeKey,
                worktreePath: activeWorktreePath(for: project),
                expanded: isVisible,
                onToggle: footerTerminalToggleAction,
                onOpenMCPControlPanel: { showMCPControlPanel = true },
                onProcessExit: { footerTerminalProcessExited(projectID: project.id) }
            )
        }
    }

    private var footerTerminalToggleAction: (() -> Void)? {
        guard footerTerminalEnabled else { return nil }
        return { toggleFooterTerminal() }
    }

    private var worktreeSwitcherItems: [WorktreeSwitcherItem] {
        projectStore.projects.flatMap { project in
            worktreeStore.list(for: project.id).map { worktree in
                WorktreeSwitcherItem(
                    projectID: project.id,
                    projectName: project.name,
                    worktree: worktree
                )
            }
        }
    }

    private var toastPosition: ToastPosition {
        ToastPosition(rawValue: toastPositionRaw) ?? .topCenter
    }

    private var toastAlignment: Alignment {
        switch toastPosition {
        case .topCenter: .top
        case .topRight: .topTrailing
        case .bottomCenter: .bottom
        case .bottomRight: .bottomTrailing
        }
    }

    private var toastEdgePadding: EdgeInsets {
        switch toastPosition {
        case .topCenter: EdgeInsets(top: 40, leading: 0, bottom: 0, trailing: 0)
        case .topRight: EdgeInsets(top: 40, leading: 0, bottom: 0, trailing: 16)
        case .bottomCenter: EdgeInsets(top: 0, leading: 0, bottom: 16, trailing: 0)
        case .bottomRight: EdgeInsets(top: 0, leading: 0, bottom: 16, trailing: 16)
        }
    }

    private var toastTransitionEdge: Edge {
        switch toastPosition {
        case .topCenter,
             .topRight: .top
        case .bottomCenter,
             .bottomRight: .bottom
        }
    }

    private var activeWorktreeKey: WorktreeKey? {
        guard let projectID = appState.activeProjectID,
              let worktreeID = appState.activeWorktreeID[projectID]
        else { return nil }
        return WorktreeKey(projectID: projectID, worktreeID: worktreeID)
    }

    private var activeProject: Project? {
        guard let pid = appState.activeProjectID else { return nil }
        return projectStore.projects.first { $0.id == pid }
    }

    private var activeCodeGraphAgentSession: KajiCodeGraphAgentSession? {
        guard let key = activeWorktreeKey else { return nil }
        guard codeGraphAgentCoordinator.isVisible(projectID: key.projectID, worktreeID: key.worktreeID) else { return nil }
        return codeGraphAgentCoordinator.session(projectID: key.projectID, worktreeID: key.worktreeID)
    }

    private var parentAgentSelected: Bool {
        appState.isParentAgentHomePresented
    }

    private var activeQuickOpenProjectPath: String? {
        guard let project = activeProject else { return nil }
        return activeWorktreePath(for: project)
    }

    private var windowTitle: String {
        if appState.isParentAgentHomePresented {
            return "Kaji"
        }
        guard let project = activeProject else { return "Kaji" }
        guard let tabTitle = appState.activeTab(for: project.id)?.title,
              !tabTitle.isEmpty
        else { return project.name }
        return "\(project.name) — \(tabTitle)"
    }

    private var activeProjectWithWorkspace: Project? {
        guard let project = activeProject,
              appState.workspaceRoot(for: project.id) != nil
        else { return nil }
        return project
    }

    private var showsWorkspaceTabBar: Bool {
        guard !appState.isParentAgentHomePresented,
              let project = activeProject,
              let workspace = appState.workspace(for: project.id)
        else { return false }
        return workspace.activeTab?.activeArea != nil
    }

    private var topBarSearchTitle: String {
        guard let project = activeProject else { return "Search Kaji" }
        return "Search \(project.name) - local..."
    }

    private func resolvedActiveWorktree(for project: Project) -> Worktree? {
        worktreeStore.preferred(for: project.id, matching: appState.activeWorktreeID[project.id])
    }

    private var shortcutDispatcher: ShortcutActionDispatcher {
        ShortcutActionDispatcher(
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore,
            ghostty: ghostty
        )
    }

    private func mountedWorktreeKeys(for project: Project) -> [WorktreeKey] {
        appState.workspaceRoots.keys
            .filter { $0.projectID == project.id }
            .sorted { $0.worktreeID.uuidString < $1.worktreeID.uuidString }
    }

    private func handleShortcutAction(_ action: ShortcutAction) -> Bool {
        let handled = shortcutDispatcher.perform(action, activeProject: activeProject) { project in
            openVCS(for: project)
        }
        guard handled else { return false }
        if action.exitsParentAgentHome {
            activateWorkspace()
        }
        return true
    }

    private func performCommand(_ command: AppCommand) {
        let dispatcher = AppCommandDispatcher(
            shortcutDispatcher: shortcutDispatcher,
            activeProject: activeProject
        ) { project in
            openVCS(for: project)
        }
        if dispatcher.perform(command), command.id.exitsParentAgentHome {
            activateWorkspace()
        }
    }

    private var activeProjectHasSplitWorkspace: Bool {
        guard let project = activeProject,
              let root = appState.workspaceRoot(for: project.id)
        else { return false }
        if case .split = root { return true }
        return false
    }

    private var projectsWithWorkspaces: [Project] {
        projectStore.projects.filter { appState.workspaceRoot(for: $0.id) != nil }
    }

    private func activateWorkspace() {
        appState.hideParentAgentHome()
    }

    private func sidePanelResizeHandle(onDrag: @escaping (CGFloat) -> Void) -> some View {
        SidePanelResizeHandle(onDrag: onDrag)
            .frame(width: BrowserLayout.resizeHandleWidth)
            .accessibilityHidden(true)
    }

    private var activeBrowserState: BrowserPaneState? {
        guard let project = activeProject,
              let key = appState.activeWorktreeKey(for: project.id)
        else { return nil }
        return browserSessions[key]?.state
    }

    private func ensureBrowserState(for project: Project) {
        guard let key = appState.activeWorktreeKey(for: project.id) else { return }
        let path = activeWorktreePath(for: project)
        if let existing = browserSessions[key], existing.state.projectPath == path {
            existing.touch()
            existing.registerControl(close: { closeBrowserSession(for: key) })
            enforceBrowserSessionLimit(activeKey: key)
            return
        }
        browserSessions[key]?.close()
        let session = BrowserSession(key: key, state: BrowserPaneState(projectPath: path))
        session.registerControl(close: { closeBrowserSession(for: key) })
        browserSessions[key] = session
        enforceBrowserSessionLimit(activeKey: key)
    }

    private func pruneBrowserStates() {
        let validKeys = validVCSKeys()
        let staleKeys = browserSessions.keys.filter { !validKeys.contains($0) }
        for key in staleKeys {
            browserSessions.removeValue(forKey: key)?.close()
        }
        enforceBrowserSessionLimit(activeKey: activeWorktreeKey)
    }

    private func enforceBrowserSessionLimit(activeKey: WorktreeKey?) {
        let overflow = browserSessions.count - BrowserLayout.maxRetainedSessions
        guard overflow > 0 else { return }
        let removable = browserSessions.values
            .filter { $0.key != activeKey }
            .sorted { $0.lastUsedAt < $1.lastUsedAt }
            .prefix(overflow)
        for session in removable {
            browserSessions.removeValue(forKey: session.key)?.close()
        }
    }

    private func closeBrowserFeature() {
        hideBrowserPanel()
        browserSessions.values.forEach { $0.close() }
        browserSessions.removeAll()
    }

    private func hideBrowserPanel() {
        withSidePanelAnimation {
            browserPanelVisible = false
            browserPanelKey = nil
        }
    }

    private func closeBrowserSession(for key: WorktreeKey) {
        browserSessions.removeValue(forKey: key)?.close()
        if browserPanelKey == key {
            hideBrowserPanel()
        }
    }

    private var isBrowserPanelVisibleForActiveWorktree: Bool {
        browserPanelVisible && browserPanelKey == activeWorktreeKey
    }

    private func toggleBrowserPanel() {
        guard browserEnabled else {
            closeBrowserFeature()
            return
        }
        guard let project = activeProject else {
            hideBrowserPanel()
            return
        }

        activateWorkspace()
        ensureBrowserState(for: project)
        guard let key = activeWorktreeKey else { return }
        let isShowing = !(browserPanelVisible && browserPanelKey == key)
        withSidePanelAnimation {
            browserPanelVisible = isShowing
            browserPanelKey = isShowing ? key : nil
            if isShowing {
                vcsPanelVisible = false
                fileTreePanelVisible = false
                agentInstructionPanelVisible = false
            }
        }
    }

    private func showBrowserPanel() {
        guard browserEnabled else {
            closeBrowserFeature()
            return
        }
        guard let project = activeProject else {
            hideBrowserPanel()
            return
        }

        activateWorkspace()
        ensureBrowserState(for: project)
        guard let key = activeWorktreeKey else { return }
        withSidePanelAnimation {
            browserPanelVisible = true
            browserPanelKey = key
            vcsPanelVisible = false
            fileTreePanelVisible = false
            agentInstructionPanelVisible = false
        }
    }

    private var activeFileTreeState: FileTreeState? {
        guard let project = activeProject,
              let key = appState.activeWorktreeKey(for: project.id)
        else { return nil }
        return fileTreeStates[key]
    }

    private func ensureFileTreeState(for project: Project) {
        guard let key = appState.activeWorktreeKey(for: project.id) else { return }
        let path = activeWorktreePath(for: project)
        if let existing = fileTreeStates[key], existing.rootPath == path { return }
        fileTreeStates[key] = FileTreeState(rootPath: path)
    }

    private var activeEditorFilePath: String? {
        guard let project = activeProject else { return nil }
        return appState.activeTab(for: project.id)?.content.editorState?.filePath
    }

    private var activeEditorState: EditorTabState? {
        guard let project = activeProject else { return nil }
        return appState.activeTab(for: project.id)?.content.editorState
    }

    private func syncFileTreeSelection(filePath: String?) {
        guard fileTreePanelVisible,
              let project = activeProject,
              let key = appState.activeWorktreeKey(for: project.id),
              let state = fileTreeStates[key]
        else { return }
        if let filePath {
            state.revealFile(at: filePath)
        } else {
            state.clearSelection()
        }
    }

    private func pruneFileTreeStates() {
        let validKeys = validVCSKeys()
        fileTreeStates = fileTreeStates.filter { validKeys.contains($0.key) }
    }

    private func toggleAttachedVCSPanel() {
        guard let project = activeProject else {
            withSidePanelAnimation { vcsPanelVisible = false }
            return
        }

        activateWorkspace()
        ensureVCSState(for: project)
        let isShowing = !vcsPanelVisible
        withSidePanelAnimation {
            vcsPanelVisible = isShowing
            if isShowing {
                fileTreePanelVisible = false
                browserPanelVisible = false
                browserPanelKey = nil
                agentInstructionPanelVisible = false
            }
        }
    }

    private func toggleFileTreePanel() {
        guard let project = activeProject else {
            withSidePanelAnimation { fileTreePanelVisible = false }
            return
        }

        activateWorkspace()
        ensureFileTreeState(for: project)
        let isShowing = !fileTreePanelVisible
        withSidePanelAnimation {
            fileTreePanelVisible = isShowing
            if isShowing {
                vcsPanelVisible = false
                globalSearchPanelVisible = false
                problemsPanelVisible = false
                browserPanelVisible = false
                browserPanelKey = nil
                agentInstructionPanelVisible = false
            }
        }
    }

    private func toggleGlobalSearchPanel() {
        guard activeProject != nil else {
            withSidePanelAnimation { globalSearchPanelVisible = false }
            return
        }

        activateWorkspace()
        let isShowing = !globalSearchPanelVisible
        withSidePanelAnimation {
            globalSearchPanelVisible = isShowing
            if isShowing {
                vcsPanelVisible = false
                fileTreePanelVisible = false
                problemsPanelVisible = false
                browserPanelVisible = false
                browserPanelKey = nil
                agentInstructionPanelVisible = false
            }
        }
    }

    private func toggleProblemsPanel() {
        guard let projectID = appState.activeProjectID else { return }
        appState.openProblemsTab(projectID: projectID)
        activateWorkspace()
    }

    private func toggleAgentInstructionPanel() {
        guard let project = activeProject else {
            withSidePanelAnimation { agentInstructionPanelVisible = false }
            return
        }

        activateWorkspace()
        agentInstructionState.refresh(
            projectPath: activeWorktreePath(for: project),
            enabledLaunchers: cliLauncherSettings.enabledLaunchers
        )
        let isShowing = !agentInstructionPanelVisible
        withSidePanelAnimation {
            agentInstructionPanelVisible = isShowing
            if isShowing {
                vcsPanelVisible = false
                fileTreePanelVisible = false
                browserPanelVisible = false
                browserPanelKey = nil
            }
        }
    }

    private var activeVCSState: VCSTabState? {
        guard let project = activeProject,
              let key = appState.activeWorktreeKey(for: project.id)
        else { return nil }
        return vcsStates[key]
    }

    private func ensureVCSState(for project: Project) {
        guard let key = appState.activeWorktreeKey(for: project.id) else { return }
        guard vcsStates[key] == nil else { return }
        vcsStates[key] = VCSTabState(projectPath: activeWorktreePath(for: project))
    }

    private func activeWorktreePath(for project: Project) -> String {
        guard let key = appState.activeWorktreeKey(for: project.id) else { return project.path }
        return worktreeStore
            .worktree(projectID: project.id, worktreeID: key.worktreeID)?
            .path ?? project.path
    }

    private func openVCS(for project: Project, preferredAreaID: UUID? = nil) {
        _ = preferredAreaID
        activateWorkspace()
        ensureVCSState(for: project)
        let isShowing = !vcsPanelVisible
        withSidePanelAnimation {
            vcsPanelVisible = isShowing
            if isShowing {
                fileTreePanelVisible = false
                browserPanelVisible = false
                browserPanelKey = nil
                agentInstructionPanelVisible = false
            }
        }
    }

    private func toggleFooterTerminal() {
        guard footerTerminalEnabled else { return }
        guard let project = activeProject else { return }
        if footerTerminalStore.isVisible(for: project.id) {
            collapseFooterTerminal(projectID: project.id)
            return
        }
        footerTerminalCleanupTasks[project.id]?.cancel()
        footerTerminalCleanupTasks[project.id] = nil
        withAnimation(KajiMotion.preferred(KajiMotion.modal, reduceMotion: reduceMotion)) {
            _ = footerTerminalStore.show(projectID: project.id, projectPath: activeWorktreePath(for: project))
        }
    }

    private func collapseFooterTerminal(projectID: UUID) {
        withAnimation(KajiMotion.preferred(KajiMotion.modal, reduceMotion: reduceMotion)) {
            footerTerminalStore.collapse(projectID: projectID)
        }
        scheduleFooterTerminalCleanupIfIdle(projectID: projectID)
    }

    private func collapseAllFooterTerminals() {
        let projectIDs = Array(footerTerminalCleanupTasks.keys) + projectStore.projects.map(\.id)
        withAnimation(KajiMotion.preferred(KajiMotion.modal, reduceMotion: reduceMotion)) {
            footerTerminalStore.collapseAll()
        }
        for projectID in Set(projectIDs) {
            scheduleFooterTerminalCleanupIfIdle(projectID: projectID)
        }
    }

    private func scheduleFooterTerminalCleanupIfIdle(projectID: UUID) {
        footerTerminalCleanupTasks[projectID]?.cancel()
        guard let state = footerTerminalStore.state(for: projectID),
              !TerminalViewRegistry.shared.needsConfirmQuit(for: state.id)
        else { return }
        footerTerminalCleanupTasks[projectID] = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(360))
            guard !Task.isCancelled else { return }
            cleanupIdleFooterTerminal(projectID: projectID)
        }
    }

    private func cleanupIdleFooterTerminal(projectID: UUID) {
        guard let state = footerTerminalStore.state(for: projectID),
              !footerTerminalStore.isVisible(for: projectID),
              !TerminalViewRegistry.shared.needsConfirmQuit(for: state.id)
        else { return }
        TerminalViewRegistry.shared.removeView(for: state.id)
        _ = footerTerminalStore.remove(projectID: projectID)
        footerTerminalCleanupTasks[projectID] = nil
    }

    private func withSidePanelAnimation(_ updates: () -> Void) {
        withAnimation(KajiMotion.preferred(KajiMotion.panel, reduceMotion: reduceMotion), updates)
    }

    private func footerTerminalProcessExited(projectID: UUID) {
        withAnimation(KajiMotion.preferred(KajiMotion.modal, reduceMotion: reduceMotion)) {
            footerTerminalStore.collapse(projectID: projectID)
        }
        scheduleFooterTerminalCleanupIfIdle(projectID: projectID)
    }

    private func requestCreateWorktree(projectID: UUID) {
        activateWorkspace()
        showQuickOpen = false
        showWorktreeSwitcher = false
        showSettings = false
        createWorktreeProjectID = projectID
    }

    private func handleCreateWorktreeResult(_ result: CreateWorktreeResult, project: Project) {
        guard case let .created(worktree, runSetup) = result else { return }
        appState.selectWorktree(projectID: project.id, worktree: worktree)
        ToastState.shared.show("Worktree created")
        guard runSetup,
              let paneID = appState.focusedArea(for: project.id)?.activeTab?.content.pane?.id
        else { return }
        ToastState.shared.show("Running worktree setup…")
        Task {
            await WorktreeSetupRunner.run(
                sourceProjectPath: project.path,
                paneID: paneID
            )
        }
    }

    private func pruneVCSStates() {
        let validKeys = validVCSKeys()
        vcsStates = vcsStates.filter { validKeys.contains($0.key) }
    }

    private func validVCSKeys() -> Set<WorktreeKey> {
        var keys: Set<WorktreeKey> = []
        for project in projectStore.projects {
            for worktree in worktreeStore.list(for: project.id) {
                keys.insert(WorktreeKey(projectID: project.id, worktreeID: worktree.id))
            }
        }
        return keys
    }

    private var vcsPruneSignature: [String] {
        var result: [String] = []
        for project in projectStore.projects {
            result.append(project.id.uuidString)
            for worktree in worktreeStore.list(for: project.id) {
                result.append(worktree.id.uuidString)
            }
        }
        return result
    }

    private var vcsEnsureSignature: String {
        let projectID = appState.activeProjectID?.uuidString ?? ""
        let worktreeID = appState.activeProjectID.flatMap { appState.activeWorktreeID[$0] }?.uuidString ?? ""
        return "\(projectID):\(worktreeID)"
    }

    private func presentCloseConfirmation(_ kind: CloseConfirmationKind) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              window.attachedSheet == nil
        else { return }

        let alert = NSAlert()
        alert.messageText = kind.title
        alert.informativeText = kind.message
        alert.alertStyle = .warning
        alert.icon = NSApp.applicationIconImage

        switch kind {
        case .unsavedEditor:
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Don't Save")
            alert.buttons[0].keyEquivalent = "\r"
            alert.buttons[1].keyEquivalent = "\u{1b}"
            alert.buttons[2].keyEquivalent = "d"
            alert.buttons[2].keyEquivalentModifierMask = [.command]
        case .lastTab,
             .runningProcess:
            alert.addButton(withTitle: "Close")
            alert.addButton(withTitle: "Cancel")
            alert.buttons[0].keyEquivalent = "\r"
            alert.buttons[1].keyEquivalent = "\u{1b}"
        }

        if kind == .runningProcess {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Don't ask again"
        }

        alert.beginSheetModal(for: window) { response in
            switch kind {
            case .lastTab:
                if response == .alertFirstButtonReturn {
                    appState.confirmCloseLastTab()
                } else {
                    appState.cancelCloseLastTab()
                }
            case .unsavedEditor:
                switch response {
                case .alertFirstButtonReturn:
                    appState.saveAndCloseUnsavedEditorTab()
                case .alertThirdButtonReturn:
                    appState.confirmCloseUnsavedEditorTab()
                default:
                    appState.cancelCloseUnsavedEditorTab()
                }
            case .runningProcess:
                if response == .alertFirstButtonReturn {
                    if alert.suppressionButton?.state == .on {
                        TabCloseConfirmationPreferences.confirmRunningProcess = false
                    }
                    appState.confirmCloseRunningTab()
                } else {
                    appState.cancelCloseRunningTab()
                }
            }
        }
    }

    private func presentSaveErrorAlert(message: String) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              window.attachedSheet == nil
        else {
            appState.pendingSaveErrorMessage = nil
            return
        }

        let alert = NSAlert()
        alert.messageText = "Could Not Save File"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "OK")
        alert.buttons[0].keyEquivalent = "\r"

        alert.beginSheetModal(for: window) { _ in
            appState.pendingSaveErrorMessage = nil
        }
    }

    private func presentLanguagePackInstallToast() {
        guard let pending = appState.pendingLanguagePackInstall else { return }
        let fileName = (pending.filePath as NSString).lastPathComponent
        ToastState.shared.showAction(
            message: "Install \(pending.entry.name) support for \(fileName)?",
            actionTitle: "Install"
        ) {
            appState.finishLanguagePackInstall(LanguagePackInstaller.install(pending.entry))
        }
    }
}

private struct WindowTitleUpdater: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.title = title
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window, window.title != title else { return }
        window.title = title
    }
}

private extension ShortcutAction {
    var exitsParentAgentHome: Bool {
        switch self {
        case .ask,
             .commandPalette,
             .agentCommandCenter,
             .toggleSidebar,
             .toggleThemePicker,
             .toggleAIUsage,
             .toggleFooterTerminal,
             .navigateBack,
             .navigateForward,
             .openProject,
             .newProject,
             .reloadConfig:
            false
        case .quickOpen,
             .switchWorktree,
             .openVCSTab,
             .toggleFileTree,
             .toggleGlobalSearch,
             .toggleProblemsPanel,
             .newTab,
             .closeTab,
             .renameTab,
             .pinUnpinTab,
             .splitRight,
             .splitDown,
             .closePane,
             .focusPaneLeft,
             .focusPaneRight,
             .focusPaneUp,
             .focusPaneDown,
             .nextTab,
             .previousTab,
             .selectTab1,
             .selectTab2,
             .selectTab3,
             .selectTab4,
             .selectTab5,
             .selectTab6,
             .selectTab7,
             .selectTab8,
             .selectTab9,
             .nextProject,
             .previousProject,
             .selectProject1,
             .selectProject2,
             .selectProject3,
             .selectProject4,
             .selectProject5,
             .selectProject6,
             .selectProject7,
             .selectProject8,
             .selectProject9,
             .findInTerminal,
             .replaceInEditor,
             .goToSymbol,
             .goToLine,
             .inlineEdit,
             .saveFile:
            true
        }
    }
}

private struct FileTreeSelectionSync: ViewModifier {
    let filePath: String?
    let panelVisible: Bool
    let sync: (String?) -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: filePath) { _, newValue in
                sync(newValue)
            }
            .onChange(of: panelVisible) { _, visible in
                guard visible else { return }
                sync(filePath)
            }
    }
}

private struct MainWindowShortcutInterceptor: NSViewRepresentable {
    let onShortcut: (ShortcutAction) -> Bool
    let onMouseBack: () -> Void
    let onMouseForward: () -> Void

    func makeNSView(context: Context) -> ShortcutInterceptingView {
        let view = ShortcutInterceptingView()
        view.onShortcut = onShortcut
        view.onMouseBack = onMouseBack
        view.onMouseForward = onMouseForward
        return view
    }

    func updateNSView(_ nsView: ShortcutInterceptingView, context: Context) {
        nsView.onShortcut = onShortcut
        nsView.onMouseBack = onMouseBack
        nsView.onMouseForward = onMouseForward
    }
}

private final class ShortcutInterceptingView: NSView {
    var onShortcut: ((ShortcutAction) -> Bool)?
    var onMouseBack: (() -> Void)?
    var onMouseForward: (() -> Void)?
    private var mouseMonitor: Any?

    deinit {
        MainActor.assumeIsolated {
            removeMouseMonitor()
            clearCallbacks()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeMouseMonitor()
        } else {
            installMouseMonitorIfNeeded()
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              ShortcutContext.isMainWindow(window)
        else { return super.performKeyEquivalent(with: event) }

        let scopes = ShortcutContext.activeScopes(for: window)
        guard let action = KeyBindingStore.shared.action(for: event, scopes: scopes) else {
            return super.performKeyEquivalent(with: event)
        }

        if onShortcut?(action) == true {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    private func installMouseMonitorIfNeeded() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .swipe]) { [weak self] event in
            guard let self,
                  let window = self.window,
                  window.isKeyWindow,
                  ShortcutContext.isMainWindow(window)
            else { return event }
            return self.handleNavigationEvent(event)
        }
    }

    private func handleNavigationEvent(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .otherMouseDown:
            switch event.buttonNumber {
            case 3:
                onMouseBack?()
                return nil
            case 4:
                onMouseForward?()
                return nil
            default:
                return event
            }
        case .swipe:
            if event.deltaX > 0 {
                onMouseBack?()
                return nil
            }
            if event.deltaX < 0 {
                onMouseForward?()
                return nil
            }
            return event
        default:
            return event
        }
    }

    private func removeMouseMonitor() {
        guard let mouseMonitor else { return }
        NSEvent.removeMonitor(mouseMonitor)
        self.mouseMonitor = nil
    }

    private func clearCallbacks() {
        onShortcut = nil
        onMouseBack = nil
        onMouseForward = nil
    }
}
