import Foundation

@MainActor
extension TabReducer {
    static func createCodeGraphTab(
        _ request: AppState.CodeGraphTabRequest,
        state: inout WorkspaceState
    ) {
        closeExistingCodeGraphTabs(state: &state)
        state.activeProjectID = request.projectID
        state.activeWorktreeID[request.projectID] = request.worktreeID
        state.activeWorktreePath[request.projectID] = request.worktreePath
        appendCodeGraphTab(request, state: &state)
    }

    private static func appendCodeGraphTab(_ request: AppState.CodeGraphTabRequest, state: inout WorkspaceState) {
        let key = WorktreeKey(projectID: request.projectID, worktreeID: request.worktreeID)
        let area = TabArea(
            projectPath: request.worktreePath,
            existingTab: TerminalTab(codeGraphState: KajiCodeGraphTabState(
                projectID: request.projectID,
                worktreeID: request.worktreeID,
                projectPath: request.worktreePath,
                graphURL: request.graphURL
            ))
        )
        let tab = WorkspaceTab(root: .tabArea(area), focusedAreaID: area.id)
        let workspace = state.workspaces[key] ?? WorktreeWorkspace()
        workspace.appendTab(tab)
        state.workspaces[key] = workspace
        WorkspaceReducerShared.refreshActiveTabMirrors(for: key, state: &state)
    }

    private static func closeExistingCodeGraphTabs(state: inout WorkspaceState) {
        for key in Array(state.workspaces.keys) {
            guard let workspace = state.workspaces[key] else { continue }
            let ids = codeGraphTabIDs(in: workspace)
            guard !ids.isEmpty else { continue }
            for id in ids {
                _ = workspace.removeTab(id)
            }
            if workspace.tabs.isEmpty {
                WorkspaceReducerShared.clearWorkspace(key: key, state: &state)
            } else {
                WorkspaceReducerShared.refreshActiveTabMirrors(for: key, state: &state)
            }
        }
    }

    private static func codeGraphTabIDs(in workspace: WorktreeWorkspace) -> [UUID] {
        workspace.tabs
            .filter { tab in
                tab.root.allAreas().contains { area in
                    area.tabs.contains { $0.kind == .codeGraph }
                }
            }
            .map(\.id)
    }
}
