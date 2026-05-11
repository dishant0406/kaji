import Foundation

@MainActor
enum WorkspaceReducerShared {
    struct FocusedAreaResolution {
        let key: WorktreeKey
        let area: TabArea
        let created: Bool
    }

    static func activeKey(projectID: UUID, state: WorkspaceState) -> WorktreeKey? {
        guard let worktreeID = state.activeWorktreeID[projectID] else { return nil }
        return WorktreeKey(projectID: projectID, worktreeID: worktreeID)
    }

    static func activeProjectPath(projectID: UUID, state: WorkspaceState) -> String? {
        state.activeWorktreePath[projectID]
    }

    static func activeWorkspace(key: WorktreeKey, state: WorkspaceState) -> WorktreeWorkspace? {
        state.workspaces[key]
    }

    static func activeWorkspaceTab(key: WorktreeKey, state: WorkspaceState) -> WorkspaceTab? {
        state.workspaces[key]?.activeTab
    }

    static func resolveArea(key: WorktreeKey, areaID: UUID?, state: WorkspaceState) -> TabArea? {
        guard let root = state.workspaceRoots[key] ?? activeWorkspaceTab(key: key, state: state)?.root else { return nil }
        if let areaID {
            return root.findArea(id: areaID)
        }
        guard let focusedID = state.focusedAreaID[key] ?? activeWorkspaceTab(key: key, state: state)?.focusedAreaID else {
            return root.allAreas().first
        }
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
        let area = createArea(worktreePath)
        let tab = WorkspaceTab(root: .tabArea(area), focusedAreaID: area.id)
        let workspace = state.workspaces[key] ?? WorktreeWorkspace()
        workspace.appendTab(tab)
        state.workspaces[key] = workspace
        refreshActiveTabMirrors(for: key, state: &state)
        return (key, area)
    }

    static func resolveOrCreateFocusedArea(
        projectID: UUID,
        areaID: UUID?,
        state: inout WorkspaceState,
        createArea: (String) -> TabArea
    ) -> FocusedAreaResolution? {
        guard let key = activeKey(projectID: projectID, state: state) else { return nil }
        if state.workspaces[key]?.activeTab == nil {
            guard let created = resolveOrCreateArea(
                projectID: projectID,
                areaID: areaID,
                state: &state,
                createArea: createArea
            )
            else { return nil }
            return FocusedAreaResolution(key: created.key, area: created.area, created: true)
        }
        guard let area = resolveArea(key: key, areaID: areaID, state: state) else { return nil }
        return FocusedAreaResolution(key: key, area: area, created: false)
    }

    static func clearWorkspace(key: WorktreeKey, state: inout WorkspaceState) {
        state.workspaces.removeValue(forKey: key)
        state.workspaceRoots.removeValue(forKey: key)
        state.focusedAreaID.removeValue(forKey: key)
        state.focusHistory.removeValue(forKey: key)
    }

    static func handleProjectEmptiedIfNeeded(
        projectID: UUID,
        state: inout WorkspaceState,
        effects: inout WorkspaceSideEffects
    ) {
        let hasAnyWorkspace = state.workspaces.keys.contains { $0.projectID == projectID }
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
        guard let root = state.workspaceRoots[key] ?? activeWorkspaceTab(key: key, state: state)?.root else { return nil }
        if case let .tabArea(area) = root {
            return area.projectPath
        }
        return root.allAreas().first?.projectPath
    }

    static func flushMirrorsIntoActiveTabs(state: inout WorkspaceState) {
        for (key, workspace) in state.workspaces {
            guard let tab = workspace.activeTab else { continue }
            if let root = state.workspaceRoots[key] {
                tab.root = root
            }
            if let focusedAreaID = state.focusedAreaID[key] {
                tab.focusedAreaID = focusedAreaID
            }
            if let focusHistory = state.focusHistory[key] {
                tab.focusHistory = focusHistory
            }
        }
    }

    static func refreshActiveTabMirrors(state: inout WorkspaceState) {
        for key in state.workspaces.keys {
            refreshActiveTabMirrors(for: key, state: &state)
        }
    }

    static func refreshActiveTabMirrors(for key: WorktreeKey, state: inout WorkspaceState) {
        guard let workspace = state.workspaces[key], let tab = workspace.activeTab else {
            state.workspaceRoots.removeValue(forKey: key)
            state.focusedAreaID.removeValue(forKey: key)
            state.focusHistory.removeValue(forKey: key)
            return
        }
        state.workspaceRoots[key] = tab.root
        state.focusedAreaID[key] = tab.focusedAreaID
        state.focusHistory[key] = tab.focusHistory
    }
}
