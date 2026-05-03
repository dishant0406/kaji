import AppKit
import SwiftUI

struct MainWindow: View {
    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore
    @Environment(WorktreeStore.self) private var worktreeStore
    @Environment(GhosttyService.self) private var ghostty
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

    @State private var vcsPanelVisible = false
    @State private var vcsPanelWidth: CGFloat = AttachedVCSLayout.defaultWidth
    @State private var vcsStates: [WorktreeKey: VCSTabState] = [:]
    @State private var fileTreePanelVisible = false
    @AppStorage("droid.fileTreeWidth") private var fileTreePanelWidth: Double = .init(FileTreeLayout.defaultWidth)
    @State private var fileTreeStates: [WorktreeKey: FileTreeState] = [:]
    @State private var showQuickOpen = false
    @State private var showAsk = false
    @State private var showAgentCommandCenter = false
    @State private var showWorktreeSwitcher = false
    @State private var showSettings = false
    @State private var showCreateThemeModal = false
    @State private var showParentAgentHome = true
    @State private var parentAgentSettings = ParentAgentSettingsStore.shared
    @State private var createWorktreeProjectID: UUID?
    @State private var showSidebarAIUsagePopover = false
    @State private var isFullScreen = false
    @State private var sidebarExpanded = UserDefaults.standard.bool(forKey: "droid.sidebarExpanded")
    @AppStorage(AppearanceSettingsKeys.sidebarTransparencyEnabled) private var sidebarTransparencyEnabled = false
    @AppStorage(AppearanceSettingsKeys.interfaceTransparencyAmount) private var interfaceTransparencyAmount = 0.7
    @AppStorage("droid.notifications.toastPosition") private var toastPositionRaw = ToastPosition.topCenter.rawValue
    private let trafficLightWidth: CGFloat = 75

    var body: some View {
        configuredMainLayout
    }

    private var configuredMainLayout: AnyView {
        let base = AnyView(
            mainLayout
                .environment(
                    \.overlayActive,
                    showQuickOpen || showAsk || showAgentCommandCenter || showWorktreeSwitcher || showSettings || showCreateThemeModal ||
                        createWorktreeProjectID != nil
                )
                .overlay(alignment: toastAlignment) {
                    toastOverlay
                }
                .overlay {
                    quickOpenOverlay
                }
                .overlay {
                    askOverlay
                }
                .overlay {
                    agentCommandCenterOverlay
                }
                .overlay {
                    worktreeSwitcherOverlay
                }
                .overlay {
                    settingsOverlay
                }
                .overlay {
                    createWorktreeOverlay
                }
                .overlay {
                    createThemeOverlay
                }
                .animation(.easeInOut(duration: 0.15), value: showSettings)
                .animation(.easeInOut(duration: 0.15), value: showCreateThemeModal)
                .animation(.easeInOut(duration: 0.15), value: createWorktreeProjectID)
                .animation(.easeInOut(duration: 0.2), value: ToastState.shared.message != nil)
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
                .onReceive(NotificationCenter.default.publisher(for: .quickOpen)) { _ in
                    showQuickOpen.toggle()
                }
                .onReceive(NotificationCenter.default.publisher(for: .ask)) { _ in
                    let shouldShow = !showAsk
                    showQuickOpen = false
                    showAgentCommandCenter = false
                    showWorktreeSwitcher = false
                    showAsk = shouldShow
                }
                .onReceive(NotificationCenter.default.publisher(for: .agentCommandCenter)) { _ in
                    let shouldShow = !showAgentCommandCenter
                    showQuickOpen = false
                    showAsk = false
                    showWorktreeSwitcher = false
                    showAgentCommandCenter = shouldShow
                }
                .onReceive(NotificationCenter.default.publisher(for: .showParentAgentHome)) { _ in
                    guard parentAgentSettings.isEnabled else {
                        showSettings = true
                        return
                    }
                    showParentAgentHome = true
                    showQuickOpen = false
                    showAsk = false
                    showAgentCommandCenter = false
                    showWorktreeSwitcher = false
                }
                .onReceive(NotificationCenter.default.publisher(for: .hideParentAgentHome)) { _ in
                    showParentAgentHome = false
                }
                .onReceive(NotificationCenter.default.publisher(for: .switchWorktree)) { _ in
                    showWorktreeSwitcher.toggle()
                }
                .onReceive(NotificationCenter.default.publisher(for: .toggleSettings)) { _ in
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
        )

        let receives2 = AnyView(
            receives1
                .onReceive(NotificationCenter.default.publisher(for: .dismissSettings)) { _ in
                    showSettings = false
                }
                .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        sidebarExpanded.toggle()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .windowFullScreenDidChange)) { notification in
                    isFullScreen = notification.userInfo?["isFullScreen"] as? Bool ?? false
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
        )

        let changes1 = AnyView(
            receives3
                .onChange(of: vcsPruneSignature) {
                    pruneVCSStates()
                    pruneFileTreeStates()
                }
                .onChange(of: vcsEnsureSignature) {
                    guard let project = activeProject else { return }
                    if vcsPanelVisible {
                        ensureVCSState(for: project)
                    }
                    if fileTreePanelVisible {
                        ensureFileTreeState(for: project)
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
        )
    }

    private var mainLayout: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if !isFullScreen {
                    Color.clear
                        .frame(width: topBarLeadingWidth)
                        .fixedSize(horizontal: true, vertical: false)
                }
                topBarContent
            }
            .frame(height: 38)
            .background(WindowDragRepresentable())
            .background(
                ChromeBackgroundSurface(
                    transparencyEnabled: sidebarTransparencyEnabled,
                    transparencyAmount: interfaceTransparencyAmount
                )
            )

            Rectangle().fill(DroidTheme.border).frame(height: 1)
                .background(
                    ChromeBackgroundSurface(
                        transparencyEnabled: sidebarTransparencyEnabled,
                        transparencyAmount: interfaceTransparencyAmount
                    )
                )

            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    Sidebar(
                        showAIUsagePopover: $showSidebarAIUsagePopover,
                        parentAgentSelected: $showParentAgentHome,
                        parentAgentEnabled: parentAgentSettings.isEnabled
                    )
                    Rectangle().fill(DroidTheme.border).frame(width: 1)
                        .accessibilityHidden(true)
                }
                .fixedSize(horizontal: true, vertical: false)
                .background(
                    SidebarBackgroundSurface(
                        transparencyEnabled: sidebarTransparencyEnabled,
                        transparencyAmount: interfaceTransparencyAmount
                    )
                )

                ZStack {
                    DroidTheme.bg
                    workspaceContent
                        .opacity(showParentAgentHome ? 0 : 1)
                        .allowsHitTesting(!showParentAgentHome)
                        .environment(\.workspaceOccluded, showParentAgentHome)
                        .zIndex(0)
                    if showParentAgentHome && parentAgentSettings.isEnabled {
                        ParentAgentHome { prompt in
                            handleParentAgentPrompt(prompt)
                        }
                        .zIndex(1)
                    }
                }

                if vcsPanelVisible, let state = activeVCSState {
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
                } else if fileTreePanelVisible, let treeState = activeFileTreeState {
                    HStack(spacing: 0) {
                        sidePanelResizeHandle { delta in
                            let next = fileTreePanelWidth - Double(delta)
                            fileTreePanelWidth = max(
                                Double(FileTreeLayout.minWidth),
                                min(Double(FileTreeLayout.maxWidth), next)
                            )
                        }
                        FileTreeView(
                            state: treeState,
                            onOpenFile: { filePath in
                                guard let projectID = appState.activeProjectID else { return }
                                appState.openFile(filePath, projectID: projectID)
                            },
                            onOpenTerminal: { directory in
                                guard let projectID = appState.activeProjectID else { return }
                                appState.dispatch(.createTabInDirectory(
                                    projectID: projectID,
                                    areaID: nil,
                                    directory: directory
                                ))
                            },
                            onFileMoved: { oldPath, newPath in
                                appState.handleFileMoved(from: oldPath, to: newPath)
                            }
                        )
                        .id(treeState.rootPath)
                        .frame(width: CGFloat(fileTreePanelWidth))
                    }
                }
            }
        }
    }

    private func handleParentAgentPrompt(_ prompt: String) {
        if ParentAgentController.shared.hasPendingQuestion {
            ParentAgentController.shared.answerPendingQuestion(prompt)
            return
        }
        ParentAgentController.shared.submit(
            prompt: prompt,
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore
        )
    }

    @ViewBuilder
    private var workspaceContent: some View {
        if let project = activeProject,
           appState.workspaceRoot(for: project.id) == nil,
           resolvedActiveWorktree(for: project) != nil
        {
            EmptyProjectPlaceholder(project: project) {
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
    private var toastOverlay: some View {
        if let toast = ToastState.shared.message {
            HStack(spacing: 6) {
                DroidIcon(systemName: "checkmark.circle.fill", size: 12)
                    .foregroundStyle(DroidTheme.diffAddFg)
                Text(toast)
                    .droidFont(size: 12, weight: .medium)
                    .foregroundStyle(DroidTheme.fg)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(DroidTheme.surface, in: RoundedRectangle(cornerRadius: DroidShape.panelRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DroidShape.panelRadius)
                    .stroke(DroidTheme.border, lineWidth: 1)
            )
            .padding(toastEdgePadding)
            .transition(.move(edge: toastTransitionEdge).combined(with: .opacity))
            .allowsHitTesting(false)
            .accessibilityLabel(toast)
            .accessibilityAddTraits(.isStaticText)
        }
    }

    @ViewBuilder
    private var quickOpenOverlay: some View {
        if showQuickOpen, let project = activeProject {
            QuickOpenOverlay(
                projectPath: activeWorktreePath(for: project),
                onSelect: { filePath in
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
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    @ViewBuilder
    private var settingsOverlay: some View {
        if showSettings {
            ZStack {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showSettings = false
                    }

                SettingsView {
                    showSettings = false
                }
                .padding(24)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
    }

    @ViewBuilder
    private var createWorktreeOverlay: some View {
        if let projectID = createWorktreeProjectID,
           let project = projectStore.projects.first(where: { $0.id == projectID })
        {
            DroidModalOverlay {
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
            DroidModalOverlay {
                showCreateThemeModal = false
            } content: {
                CreateThemeModal {
                    showCreateThemeModal = false
                }
            }
        }
    }

    @ViewBuilder
    private var topBarContent: some View {
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
                isWindowTitleBar: true,
                showVCSButton: true,
                projectID: project.id,
                onSelectTab: { tabID in
                    appState.dispatch(.selectTab(projectID: project.id, areaID: areaID, tabID: tabID))
                },
                onCreateTab: {
                    appState.dispatch(.createTab(projectID: project.id, areaID: nil))
                },
                onCreateVCSTab: {
                    openVCS(for: project, preferredAreaID: areaID)
                },
                onCloseTab: { tabID in
                    appState.closeTab(tabID, areaID: areaID, projectID: project.id)
                },
                onSplit: { dir in
                    appState.dispatch(.splitArea(.init(
                        projectID: project.id,
                        areaID: areaID,
                        direction: dir,
                        position: .second
                    )))
                },
                onDropAction: { result in
                    appState.dispatch(result.action(projectID: project.id))
                },
                onCreateTabAdjacent: { tabID, side in
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
        } else {
            WindowDragRepresentable(alwaysEnabled: true)
                .overlay {
                    HStack {
                        if let project = activeProject {
                            Text(project.name)
                                .droidFont(size: 13, weight: .semibold)
                                .foregroundStyle(DroidTheme.fgMuted)
                                .padding(.leading, 14)
                        }
                        Spacer(minLength: 0)
                    }
                    .allowsHitTesting(false)
                }
                .overlay(alignment: .trailing) {
                    HStack(spacing: 0) {
                        if let version = UpdateService.shared.availableUpdateVersion {
                            UpdateBadge(version: version) {
                                UpdateService.shared.checkForUpdates()
                            }
                            .padding(.trailing, 4)
                        }
                        if let project = activeProject, activeProjectWithWorkspace != nil {
                            IconButton(symbol: "doc.text", size: 12, accessibilityLabel: "Quick Open") {
                                NotificationCenter.default.post(name: .quickOpen, object: nil)
                            }
                            .help("Quick Open (\(KeyBindingStore.shared.combo(for: .quickOpen).displayString))")
                            FileDiffIconButton {
                                openVCS(for: project)
                            }
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
                    .padding(.trailing, 8)
                }
        }
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

    private var topBarLeadingWidth: CGFloat {
        let sidebarWidth = SidebarLayout.resolvedWidth(expanded: sidebarExpanded) + 1
        return max(trafficLightWidth, sidebarWidth)
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

    private var activeQuickOpenProjectPath: String? {
        guard let project = activeProject else { return nil }
        return activeWorktreePath(for: project)
    }

    private var windowTitle: String {
        guard let project = activeProject else { return "Droid" }
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
        shortcutDispatcher.perform(action, activeProject: activeProject) { project in
            openVCS(for: project)
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

    private func sidePanelResizeHandle(onDrag: @escaping (CGFloat) -> Void) -> some View {
        Rectangle().fill(DroidTheme.border).frame(width: 1)
            .accessibilityHidden(true)
            .overlay {
                Color.clear
                    .frame(width: 5)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { v in onDrag(v.translation.width) }
                    )
                    .onHover { on in
                        if on { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
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
            vcsPanelVisible = false
            return
        }

        ensureVCSState(for: project)
        let isShowing = !vcsPanelVisible
        vcsPanelVisible = isShowing
        if isShowing {
            fileTreePanelVisible = false
        }
    }

    private func toggleFileTreePanel() {
        guard let project = activeProject else {
            fileTreePanelVisible = false
            return
        }

        ensureFileTreeState(for: project)
        let isShowing = !fileTreePanelVisible
        fileTreePanelVisible = isShowing
        if isShowing {
            vcsPanelVisible = false
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
        ensureVCSState(for: project)
        let isShowing = !vcsPanelVisible
        vcsPanelVisible = isShowing
        if isShowing {
            fileTreePanelVisible = false
        }
    }

    private func requestCreateWorktree(projectID: UUID) {
        showQuickOpen = false
        showWorktreeSwitcher = false
        showSettings = false
        createWorktreeProjectID = projectID
    }

    private func handleCreateWorktreeResult(_ result: CreateWorktreeResult, project: Project) {
        guard case let .created(worktree, runSetup) = result else { return }
        appState.selectWorktree(projectID: project.id, worktree: worktree)
        guard runSetup,
              let paneID = appState.focusedArea(for: project.id)?.activeTab?.content.pane?.id
        else { return }
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
}
