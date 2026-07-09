import Foundation
import Testing

@testable import Kaji

@MainActor
struct AppStateTabCloseTests {
    @Test
    func closePinnedWorkspaceTabUnpinsAndRemovesIt() {
        let project = Project(name: "muxy", path: "/tmp/muxy")
        let worktreeID = UUID()
        let key = WorktreeKey(projectID: project.id, worktreeID: worktreeID)
        let firstArea = TabArea(projectPath: project.path)
        let secondArea = TabArea(projectPath: project.path)
        let first = WorkspaceTab(root: .tabArea(firstArea), focusedAreaID: firstArea.id)
        let second = WorkspaceTab(root: .tabArea(secondArea), focusedAreaID: secondArea.id)
        second.isPinned = true
        let workspace = WorktreeWorkspace(tabs: [first, second], activeTabID: second.id)
        let appState = makeAppState(project: project, worktreeID: worktreeID, workspace: workspace)

        appState.closeTab(second.id, areaID: secondArea.id, projectID: project.id)

        #expect(appState.workspace(for: project.id)?.tabs.map(\.id) == [first.id])
        #expect(appState.workspaceRoots[key]?.findArea(id: firstArea.id) != nil)
    }

    @Test
    func confirmClosePinnedLastWorkspaceTabUnpinsAndRemovesIt() {
        let previousPreference = UserDefaults.standard.object(forKey: ProjectLifecyclePreferences.keepOpenWhenNoTabsKey)
        defer {
            if let previousPreference {
                UserDefaults.standard.set(previousPreference, forKey: ProjectLifecyclePreferences.keepOpenWhenNoTabsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: ProjectLifecyclePreferences.keepOpenWhenNoTabsKey)
            }
        }
        ProjectLifecyclePreferences.keepOpenWhenNoTabs = false

        let project = Project(name: "muxy", path: "/tmp/muxy")
        let worktreeID = UUID()
        let area = TabArea(projectPath: project.path)
        let tab = WorkspaceTab(root: .tabArea(area), focusedAreaID: area.id, focusHistory: [])
        tab.isPinned = true
        let workspace = WorktreeWorkspace(tabs: [tab], activeTabID: tab.id)
        let appState = makeAppState(project: project, worktreeID: worktreeID, workspace: workspace)

        appState.closeTab(tab.id, areaID: area.id, projectID: project.id)
        #expect(appState.pendingLastTabClose != nil)

        appState.confirmCloseLastTab()

        #expect(appState.workspace(for: project.id) == nil)
        #expect(appState.activeProjectID == nil)
    }

    private func makeAppState(project: Project, worktreeID: UUID, workspace: WorktreeWorkspace) -> AppState {
        let appState = AppState(
            selectionStore: TabCloseSelectionStore(),
            terminalViews: TabCloseTerminalViews(),
            workspacePersistence: TabCloseWorkspacePersistence()
        )
        let key = WorktreeKey(projectID: project.id, worktreeID: worktreeID)
        appState.activeProjectID = project.id
        appState.activeWorktreeID[project.id] = worktreeID
        appState.activeWorktreePath[project.id] = project.path
        appState.workspaces[key] = workspace
        appState.workspaceRoots[key] = workspace.activeTab?.root
        appState.focusedAreaID[key] = workspace.activeTab?.focusedAreaID
        return appState
    }
}

private struct TabCloseSelectionStore: ActiveProjectSelectionStoring {
    func loadActiveProjectID() -> UUID? { nil }
    func saveActiveProjectID(_ id: UUID?) {}
    func loadActiveWorktreeIDs() -> [UUID: UUID] { [:] }
    func saveActiveWorktreeIDs(_ ids: [UUID: UUID]) {}
}

private struct TabCloseTerminalViews: TerminalViewRemoving {
    func removeView(for paneID: UUID) {}
    func needsConfirmQuit(for paneID: UUID) -> Bool { false }
}

private struct TabCloseWorkspacePersistence: WorkspacePersisting {
    func saveWorkspaces(_ workspaces: [WorkspaceSnapshot]) throws {}
    func loadWorkspaces() throws -> [WorkspaceSnapshot] { [] }
}
