import Foundation

struct NavigationContext {
    let projectID: UUID
    let worktreeID: UUID
    let worktreePath: String
    let areaID: UUID
    let tabID: UUID
}

@MainActor
enum NotificationNavigator {
    static func resolveContext(
        for paneID: UUID,
        appState: AppState,
        worktreeStore: WorktreeStore
    ) -> NavigationContext? {
        resolveContext(appState: appState, worktreeStore: worktreeStore) { tab in
            tab.content.pane?.id == paneID
        }
    }

    static func resolveKajiAgentContext(
        for scope: KajiAgentScope,
        appState: AppState,
        worktreeStore: WorktreeStore
    ) -> NavigationContext? {
        let key = WorktreeKey(projectID: scope.projectID, worktreeID: scope.worktreeID)
        guard let workspace = appState.workspaces[key] else { return nil }
        return resolveContext(
            key: key,
            workspace: workspace,
            appState: appState,
            worktreeStore: worktreeStore
        ) { tab in
            tab.content.parentAgentState?.id == scope.agentID
        }
    }

    static func navigate(
        to notification: KajiNotification,
        appState: AppState,
        notificationStore: NotificationStore
    ) {
        if let worktreeStore = notificationStore.worktreeStore,
           let context = resolveContext(for: notification.paneID, appState: appState, worktreeStore: worktreeStore)
        {
            navigate(to: context, appState: appState)
            notificationStore.markAsRead(notification.id)
            return
        }

        guard appState.activeWorktreeID[notification.projectID] != nil || appState.activeProjectID == notification.projectID else {
            notificationStore.markAsRead(notification.id)
            return
        }

        if appState.activeProjectID != notification.projectID
            || appState.activeWorktreeID[notification.projectID] != notification.worktreeID
        {
            appState.dispatch(.selectProject(
                projectID: notification.projectID,
                worktreeID: notification.worktreeID,
                worktreePath: notification.worktreePath
            ))
        }

        appState.dispatch(.selectTab(projectID: notification.projectID, areaID: notification.areaID, tabID: notification.tabID))
        appState.dispatch(.focusArea(projectID: notification.projectID, areaID: notification.areaID))

        notificationStore.markAsRead(notification.id)
    }

    static func navigate(to context: NavigationContext, appState: AppState) {
        appState.dispatch(.selectProject(
            projectID: context.projectID,
            worktreeID: context.worktreeID,
            worktreePath: context.worktreePath
        ))
        appState.dispatch(.selectTab(projectID: context.projectID, areaID: context.areaID, tabID: context.tabID))
        appState.dispatch(.focusArea(projectID: context.projectID, areaID: context.areaID))
    }

    static func activeTabID(appState: AppState) -> UUID? {
        guard let projectID = appState.activeProjectID,
              let key = appState.activeWorktreeKey(for: projectID)
        else { return nil }
        return appState.workspaces[key]?.activeTabID
    }

    static func isActiveTab(_ tabID: UUID, appState: AppState) -> Bool {
        activeTabID(appState: appState) == tabID
    }

    private static func resolveContext(
        appState: AppState,
        worktreeStore: WorktreeStore,
        matches: (TerminalTab) -> Bool
    ) -> NavigationContext? {
        for (key, workspace) in appState.workspaces {
            if let context = resolveContext(
                key: key,
                workspace: workspace,
                appState: appState,
                worktreeStore: worktreeStore,
                matches: matches
            ) {
                return context
            }
        }
        return nil
    }

    private static func resolveContext(
        key: WorktreeKey,
        workspace: WorktreeWorkspace,
        appState _: AppState,
        worktreeStore: WorktreeStore,
        matches: (TerminalTab) -> Bool
    ) -> NavigationContext? {
        for workspaceTab in workspace.tabs {
            for area in workspaceTab.root.allAreas() {
                for tab in area.tabs where matches(tab) {
                    let path = worktreeStore.worktree(
                        projectID: key.projectID,
                        worktreeID: key.worktreeID
                    )?.path ?? area.projectPath
                    return NavigationContext(
                        projectID: key.projectID,
                        worktreeID: key.worktreeID,
                        worktreePath: path,
                        areaID: area.id,
                        tabID: workspaceTab.id
                    )
                }
            }
        }
        return nil
    }
}
