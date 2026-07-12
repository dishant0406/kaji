import Foundation

@MainActor
struct ShortcutActionDispatcher {
    let appState: AppState
    let projectStore: ProjectStore
    let worktreeStore: WorktreeStore
    let termy: TermyService
    let notificationCenter: NotificationCenter

    init(
        appState: AppState,
        projectStore: ProjectStore,
        worktreeStore: WorktreeStore,
        termy: TermyService,
        notificationCenter: NotificationCenter = .default
    ) {
        self.appState = appState
        self.projectStore = projectStore
        self.worktreeStore = worktreeStore
        self.termy = termy
        self.notificationCenter = notificationCenter
    }

    func perform(_ action: ShortcutAction, activeProject: Project?, openVCS: (Project) -> Void) -> Bool {
        if performRegisteredCommand(action) { return true }

        if let index = action.tabSelectionIndex {
            guard let projectID = appState.activeProjectID else { return false }
            appState.selectTabByIndex(index, projectID: projectID)
            return true
        }

        if let index = action.projectSelectionIndex {
            appState.selectProjectByIndex(index, projects: projectStore.projects, worktrees: worktreeStore.worktrees)
            return true
        }

        if let index = action.paneSelectionIndex {
            guard let projectID = appState.activeProjectID else { return false }
            appState.focusPane(projectID: projectID, index: index)
            return true
        }

        if let index = action.footerLauncherIndex {
            return openFooterLauncher(index: index)
        }

        switch action {
        case .newTab:
            guard let projectID = appState.activeProjectID else { return false }
            appState.createTab(projectID: projectID)
            return true
        case .closeTab:
            guard let projectID = appState.activeProjectID else { return false }
            appState.closeActiveWorkspaceTab(projectID: projectID)
            return true
        case .renameTab:
            notificationCenter.post(name: .renameActiveTab, object: nil)
            return true
        case .pinUnpinTab:
            guard let projectID = appState.activeProjectID else { return false }
            appState.togglePinActiveTab(projectID: projectID)
            return true
        case .splitRight:
            guard let projectID = appState.activeProjectID else { return false }
            appState.splitFocusedArea(direction: .horizontal, projectID: projectID)
            return true
        case .splitDown:
            guard let projectID = appState.activeProjectID else { return false }
            appState.splitFocusedArea(direction: .vertical, projectID: projectID)
            return true
        case .closePane:
            guard let projectID = appState.activeProjectID,
                  let areaID = appState.focusedAreaID(for: projectID)
            else { return false }
            appState.closeArea(areaID, projectID: projectID)
            return true
        case .focusNextPane:
            guard let projectID = appState.activeProjectID else { return false }
            appState.focusNextPane(projectID: projectID)
            return true
        case .focusPreviousPane:
            guard let projectID = appState.activeProjectID else { return false }
            appState.focusPreviousPane(projectID: projectID)
            return true
        case .focusLastPane:
            guard let projectID = appState.activeProjectID else { return false }
            appState.focusLastPane(projectID: projectID)
            return true
        case .focusPaneLeft:
            guard let projectID = appState.activeProjectID else { return false }
            appState.focusPaneLeft(projectID: projectID)
            return true
        case .focusPaneRight:
            guard let projectID = appState.activeProjectID else { return false }
            appState.focusPaneRight(projectID: projectID)
            return true
        case .focusPaneUp:
            guard let projectID = appState.activeProjectID else { return false }
            appState.focusPaneUp(projectID: projectID)
            return true
        case .focusPaneDown:
            guard let projectID = appState.activeProjectID else { return false }
            appState.focusPaneDown(projectID: projectID)
            return true
        case .increasePaneWidth:
            return dispatchActiveProjectAction { .resizeFocusedPane(projectID: $0, command: .wider) }
        case .decreasePaneWidth:
            return dispatchActiveProjectAction { .resizeFocusedPane(projectID: $0, command: .narrower) }
        case .increasePaneHeight:
            return dispatchActiveProjectAction { .resizeFocusedPane(projectID: $0, command: .taller) }
        case .decreasePaneHeight:
            return dispatchActiveProjectAction { .resizeFocusedPane(projectID: $0, command: .shorter) }
        case .balancePanes:
            return dispatchActiveProjectAction { .balancePanes(projectID: $0) }
        case .swapPaneLeft:
            return dispatchActiveProjectAction { .swapPane(projectID: $0, direction: .left) }
        case .swapPaneRight:
            return dispatchActiveProjectAction { .swapPane(projectID: $0, direction: .right) }
        case .swapPaneUp:
            return dispatchActiveProjectAction { .swapPane(projectID: $0, direction: .up) }
        case .swapPaneDown:
            return dispatchActiveProjectAction { .swapPane(projectID: $0, direction: .down) }
        case .movePaneLeft:
            return dispatchActiveProjectAction { .movePaneInDirection(projectID: $0, direction: .left) }
        case .movePaneRight:
            return dispatchActiveProjectAction { .movePaneInDirection(projectID: $0, direction: .right) }
        case .movePaneUp:
            return dispatchActiveProjectAction { .movePaneInDirection(projectID: $0, direction: .up) }
        case .movePaneDown:
            return dispatchActiveProjectAction { .movePaneInDirection(projectID: $0, direction: .down) }
        case .nextTab:
            guard let projectID = appState.activeProjectID else { return false }
            appState.selectNextTab(projectID: projectID)
            return true
        case .previousTab:
            guard let projectID = appState.activeProjectID else { return false }
            appState.selectPreviousTab(projectID: projectID)
            return true
        case .toggleThemePicker:
            notificationCenter.post(name: .toggleThemePicker, object: nil)
            return true
        case .newProject:
            return false
        case .openProject:
            ProjectOpenService.openProject(
                appState: appState,
                projectStore: projectStore,
                worktreeStore: worktreeStore
            )
            return true
        case .reloadConfig:
            termy.reloadConfig()
            notificationCenter.post(name: .themeDidChange, object: nil)
            return true
        case .nextProject:
            appState.selectNextProject(projects: projectStore.projects, worktrees: worktreeStore.worktrees)
            return true
        case .previousProject:
            appState.selectPreviousProject(projects: projectStore.projects, worktrees: worktreeStore.worktrees)
            return true
        case .findInTerminal:
            notificationCenter.post(name: .findInTerminal, object: nil)
            return true
        case .replaceInEditor:
            notificationCenter.post(name: .replaceInEditor, object: nil)
            return true
        case .openVCSTab:
            guard let activeProject else { return false }
            openVCS(activeProject)
            return true
        case .commandPalette:
            notificationCenter.post(name: .commandPalette, object: nil)
            return true
        case .quickOpen:
            notificationCenter.post(name: .quickOpen, object: nil)
            return true
        case .ask:
            notificationCenter.post(name: .ask, object: nil)
            return true
        case .agentCommandCenter:
            notificationCenter.post(name: .agentCommandCenter, object: nil)
            return true
        case .switchWorktree:
            notificationCenter.post(name: .switchWorktree, object: nil)
            return true
        case .saveFile,
             .goToSymbol,
             .goToLine,
             .inlineEdit:
            return false
        case .toggleSidebar:
            notificationCenter.post(name: .toggleSidebar, object: nil)
            return true
        case .toggleFileTree:
            notificationCenter.post(name: .toggleFileTree, object: nil)
            return true
        case .toggleGlobalSearch:
            notificationCenter.post(name: .toggleGlobalSearch, object: nil)
            return true
        case .toggleProblemsPanel:
            notificationCenter.post(name: .toggleProblemsPanel, object: nil)
            return true
        case .toggleBrowserPanel:
            notificationCenter.post(name: .toggleBrowserPanel, object: nil)
            return true
        case .browserBack:
            notificationCenter.post(name: .browserBack, object: nil)
            return true
        case .browserForward:
            notificationCenter.post(name: .browserForward, object: nil)
            return true
        case .browserReload:
            notificationCenter.post(name: .browserReload, object: nil)
            return true
        case .browserFocusAddressBar:
            notificationCenter.post(name: .browserFocusAddressBar, object: nil)
            return true
        case .browserNewPage:
            notificationCenter.post(name: .browserNewPage, object: nil)
            return true
        case .browserClosePage:
            notificationCenter.post(name: .browserClosePage, object: nil)
            return true
        case .browserNextPage:
            notificationCenter.post(name: .browserNextPage, object: nil)
            return true
        case .browserPreviousPage:
            notificationCenter.post(name: .browserPreviousPage, object: nil)
            return true
        case .browserReadPage:
            notificationCenter.post(name: .browserReadPage, object: nil)
            return true
        case .toggleAgentInstructions:
            notificationCenter.post(name: .toggleAgentInstructions, object: nil)
            return true
        case .toggleMCPControlPanel:
            notificationCenter.post(name: .toggleMCPControlPanel, object: nil)
            return true
        case .closeActiveSidePanel:
            notificationCenter.post(name: .closeActiveSidePanel, object: nil)
            return true
        case .toggleNotificationPanel:
            notificationCenter.post(name: .toggleNotificationPanel, object: nil)
            return true
        case .toggleAgentMissionControl:
            notificationCenter.post(name: .toggleAgentMissionControl, object: nil)
            return true
        case .toggleFooterTerminal:
            notificationCenter.post(name: .toggleFooterTerminal, object: nil)
            return true
        case .openKajiAgentSplit:
            guard let projectID = appState.activeProjectID else { return false }
            appState.createParentAgentSplit(projectID: projectID)
            return true
        case .toggleAIUsage:
            guard AIUsageSettingsStore.isUsageEnabled() else { return false }
            notificationCenter.post(name: .toggleAIUsage, object: nil)
            return true
        case .navigateBack:
            guard appState.navigation.canGoBack else { return false }
            appState.goBack()
            return true
        case .navigateForward:
            guard appState.navigation.canGoForward else { return false }
            appState.goForward()
            return true
        case .vcsRefresh:
            notificationCenter.post(name: .vcsRefresh, object: nil)
            return true
        case .vcsCommit:
            notificationCenter.post(name: .vcsCommit, object: nil)
            return true
        case .vcsPull:
            notificationCenter.post(name: .vcsPull, object: nil)
            return true
        case .vcsPush:
            notificationCenter.post(name: .vcsPush, object: nil)
            return true
        case .vcsCreatePR:
            notificationCenter.post(name: .vcsCreatePR, object: nil)
            return true
        case .fileTreeNewFile:
            notificationCenter.post(name: .fileTreeNewFile, object: nil)
            return true
        case .fileTreeNewFolder:
            notificationCenter.post(name: .fileTreeNewFolder, object: nil)
            return true
        case .fileTreeToggleChangedOnly:
            notificationCenter.post(name: .fileTreeToggleChangedOnly, object: nil)
            return true
        case .selectTab1,
             .selectTab2,
             .selectTab3,
             .selectTab4,
             .selectTab5,
             .selectTab6,
             .selectTab7,
             .selectTab8,
             .selectTab9,
             .selectProject1,
             .selectProject2,
             .selectProject3,
             .selectProject4,
             .selectProject5,
             .selectProject6,
             .selectProject7,
             .selectProject8,
             .selectProject9,
             .focusPane1,
             .focusPane2,
             .focusPane3,
             .focusPane4,
             .focusPane5,
             .focusPane6,
             .focusPane7,
             .focusPane8,
             .focusPane9,
             .openFooterLauncher1,
             .openFooterLauncher2,
             .openFooterLauncher3,
             .openFooterLauncher4,
             .openFooterLauncher5:
            return false
        }
    }

    private func openFooterLauncher(index: Int) -> Bool {
        guard let projectID = appState.activeProjectID else { return false }
        let launchers = CLILauncherSettings.shared.enabledLaunchers
        guard launchers.indices.contains(index) else { return false }
        let launcher = launchers[index]
        let command = launcher.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return false }
        appState.createCommandSplit(projectID: projectID, title: launcher.definition.displayName, command: command)
        return true
    }

    private func dispatchActiveProjectAction(_ action: (UUID) -> AppState.Action) -> Bool {
        guard let projectID = appState.activeProjectID else { return false }
        appState.dispatch(action(projectID))
        return true
    }
}
