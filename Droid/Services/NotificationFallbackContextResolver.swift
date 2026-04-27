import Foundation

@MainActor
enum NotificationFallbackContextResolver {
    static func resolve(
        key: WorktreeKey,
        appState: AppState,
        worktreeStore: WorktreeStore?
    ) -> NavigationContext? {
        guard let root = appState.workspaceRoots[key] else { return nil }

        if let active = activeContext(key: key, root: root, appState: appState, worktreeStore: worktreeStore) {
            return active
        }

        for area in root.allAreas() {
            if let context = context(for: area, key: key, tabID: area.activeTabID ?? area.tabs.first?.id, worktreeStore: worktreeStore) {
                return context
            }
        }

        return nil
    }

    private static func activeContext(
        key: WorktreeKey,
        root: SplitNode,
        appState: AppState,
        worktreeStore: WorktreeStore?
    ) -> NavigationContext? {
        guard let areaID = appState.focusedAreaID[key],
              let area = root.findArea(id: areaID)
        else {
            return nil
        }

        return context(
            for: area,
            key: key,
            tabID: area.activeTabID ?? area.tabs.first?.id,
            worktreeStore: worktreeStore
        )
    }

    private static func context(
        for area: TabArea,
        key: WorktreeKey,
        tabID: UUID?,
        worktreeStore: WorktreeStore?
    ) -> NavigationContext? {
        guard let tabID else { return nil }
        let path = worktreeStore?.worktree(
            projectID: key.projectID,
            worktreeID: key.worktreeID
        )?.path ?? area.projectPath
        return NavigationContext(
            projectID: key.projectID,
            worktreeID: key.worktreeID,
            worktreePath: path,
            areaID: area.id,
            tabID: tabID
        )
    }
}
