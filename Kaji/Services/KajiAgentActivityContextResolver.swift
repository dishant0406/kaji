import Foundation

@MainActor
enum KajiAgentActivityContextResolver {
    static func context(scope: KajiAgentScope, appState: AppState, worktreeStore: WorktreeStore?) -> NavigationContext? {
        guard let worktreeStore else { return fallbackContext(scope: scope, appState: appState) }
        return NotificationNavigator.resolveKajiAgentContext(
            for: scope,
            appState: appState,
            worktreeStore: worktreeStore
        ) ?? fallbackContext(scope: scope, appState: appState)
    }

    private static func fallbackContext(scope: KajiAgentScope, appState: AppState) -> NavigationContext? {
        let key = WorktreeKey(projectID: scope.projectID, worktreeID: scope.worktreeID)
        guard let areaID = appState.focusedAreaID[key],
              let tabID = appState.workspaces[key]?.activeTabID
        else { return nil }
        return NavigationContext(
            projectID: scope.projectID,
            worktreeID: scope.worktreeID,
            worktreePath: scope.projectPath,
            areaID: areaID,
            tabID: tabID
        )
    }
}
