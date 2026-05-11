import Foundation

@MainActor
enum CodexSessionContextResolver {
    static func resolve(
        cwd: String?,
        appState: AppState,
        worktreeStore: WorktreeStore?
    ) -> NavigationContext? {
        guard let cwd else { return nil }
        let normalizedCWD = URL(fileURLWithPath: cwd).standardizedFileURL.path
        let matches = appState.workspaceRoots.compactMap { key, root -> (WorktreeKey, SplitNode)? in
            guard let path = worktreeStore?.worktree(projectID: key.projectID, worktreeID: key.worktreeID)?.path else { return nil }
            let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
            guard normalizedCWD == normalizedPath || normalizedCWD.hasPrefix(normalizedPath + "/") else { return nil }
            return (key, root)
        }
        guard let (key, root) = longestPathMatch(matches: matches, worktreeStore: worktreeStore) else { return nil }
        let area = appState.focusedAreaID[key].flatMap { root.findArea(id: $0) } ?? root.allAreas().first
        guard let area, let tab = area.activeTab ?? area.tabs.first else { return nil }
        let worktreePath = worktreeStore?.worktree(projectID: key.projectID, worktreeID: key.worktreeID)?.path ?? area.projectPath
        return NavigationContext(
            projectID: key.projectID,
            worktreeID: key.worktreeID,
            worktreePath: worktreePath,
            areaID: area.id,
            tabID: tab.id
        )
    }

    private static func longestPathMatch(
        matches: [(WorktreeKey, SplitNode)],
        worktreeStore: WorktreeStore?
    ) -> (WorktreeKey, SplitNode)? {
        matches.max { lhs, rhs in
            let lhsPath = worktreeStore?.worktree(projectID: lhs.0.projectID, worktreeID: lhs.0.worktreeID)?.path ?? ""
            let rhsPath = worktreeStore?.worktree(projectID: rhs.0.projectID, worktreeID: rhs.0.worktreeID)?.path ?? ""
            return lhsPath.count < rhsPath.count
        }
    }
}
