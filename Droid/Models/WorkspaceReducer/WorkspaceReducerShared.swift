import Foundation

@MainActor
enum WorkspaceReducerShared {
    static func activeKey(projectID: UUID, state: WorkspaceState) -> WorktreeKey? {
        guard let worktreeID = state.activeWorktreeID[projectID] else { return nil }
        return WorktreeKey(projectID: projectID, worktreeID: worktreeID)
    }

    static func activeProjectPath(projectID: UUID, state: WorkspaceState) -> String? {
        state.activeWorktreePath[projectID]
    }

    static func resolveArea(key: WorktreeKey, areaID: UUID?, state: WorkspaceState) -> TabArea? {
        guard let root = state.workspaceRoots[key] else { return nil }
        if let areaID {
            return root.findArea(id: areaID)
        }
        guard let focusedID = state.focusedAreaID[key] else { return nil }
        return root.findArea(id: focusedID)
    }

    static func resolveOrCreateArea(
        projectID: UUID,
        areaID: UUID?,
        state: inout WorkspaceState,
        createArea: (String) -> TabArea
    ) -> (key: WorktreeKey, area: TabArea)? {
        guard let worktreeID = state.activeWorktreeID[projectID],
              let worktreePath = activeProjectPath(projectID: projectID, state: state)
        else { return nil }
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        guard state.workspaceRoots[key] == nil else { return nil }
        let area = createArea(worktreePath)
        state.workspaceRoots[key] = .tabArea(area)
        state.focusedAreaID[key] = area.id
        return (key, area)
    }

    static func resolveOrCreateFocusedArea(
        projectID: UUID,
        areaID: UUID?,
        state: inout WorkspaceState,
        createArea: (String) -> TabArea
    ) -> (key: WorktreeKey, area: TabArea, created: Bool)? {
        guard let key = activeKey(projectID: projectID, state: state) else { return nil }
        if state.workspaceRoots[key] == nil {
            guard let created = resolveOrCreateArea(
                projectID: projectID,
                areaID: areaID,
                state: &state,
                createArea: createArea
            )
            else { return nil }
            return (created.key, created.area, true)
        }
        guard let area = resolveArea(key: key, areaID: areaID, state: state) else { return nil }
        return (key, area, false)
    }

    static func clearWorkspace(key: WorktreeKey, state: inout WorkspaceState) {
        state.workspaceRoots.removeValue(forKey: key)
        state.focusedAreaID.removeValue(forKey: key)
        state.focusHistory.removeValue(forKey: key)
    }

    static func handleProjectEmptiedIfNeeded(
        projectID: UUID,
        state: inout WorkspaceState,
        effects: inout WorkspaceSideEffects
    ) {
        let hasAnyWorkspace = state.workspaceRoots.keys.contains { $0.projectID == projectID }
        guard !hasAnyWorkspace else { return }
        guard !state.keepProjectOpenWhenEmpty else { return }
        state.activeWorktreeID.removeValue(forKey: projectID)
        state.activeWorktreePath.removeValue(forKey: projectID)
        if state.activeProjectID == projectID {
            state.activeProjectID = nil
        }
        effects.projectIDsToRemove.append(projectID)
    }

    static func projectPath(for key: WorktreeKey, state: WorkspaceState) -> String? {
        guard let root = state.workspaceRoots[key] else { return nil }
        if case let .tabArea(area) = root {
            return area.projectPath
        }
        return root.allAreas().first?.projectPath
    }
}
