import Foundation
import Testing

@testable import Kaji

@Suite("AppState Parent Agent")
@MainActor
struct AppStateParentAgentTests {
    private let testPath = "/tmp/test"

    @Test("openParentAgentTab opens KajiCode command tab")
    func openParentAgentTabOpensKajiCodeCommandTab() throws {
        let projectID = UUID()
        let worktreeID = UUID()
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        let terminalArea = TabArea(projectPath: testPath)
        let terminalTab = WorkspaceTab(root: .tabArea(terminalArea), focusedAreaID: terminalArea.id)
        let agentArea = TabArea(
            projectPath: testPath,
            existingTab: TerminalTab(parentAgentState: ParentAgentTabState(
                projectID: projectID,
                worktreeID: worktreeID,
                projectPath: testPath
            ))
        )
        let agentTab = WorkspaceTab(root: .tabArea(agentArea), focusedAreaID: agentArea.id)
        let workspace = WorktreeWorkspace(tabs: [terminalTab, agentTab], activeTabID: terminalTab.id)
        let appState = AppState(
            selectionStore: TestSelectionStore(),
            terminalViews: TestTerminalViewRemover(),
            workspacePersistence: TestWorkspacePersistence()
        )
        appState.activeProjectID = projectID
        appState.activeWorktreeID = [projectID: worktreeID]
        appState.activeWorktreePath = [projectID: testPath]
        appState.workspaces = [key: workspace]
        appState.workspaceRoots = [key: terminalTab.root]
        appState.focusedAreaID = [key: terminalArea.id]

        appState.openParentAgentTab(projectID: projectID)

        let updatedWorkspace = try #require(appState.workspaces[key])
        let activeTab = try #require(updatedWorkspace.activeTab)
        let activeContent = try #require(activeTab.activeContent)
        let pane = try #require(activeContent.content.pane)
        #expect(updatedWorkspace.tabs.count == 3)
        #expect(updatedWorkspace.activeTabID != agentTab.id)
        #expect(pane.title == "KajiCode")
        #expect(pane.injectedCommand?.contains("kajicode") == true)
    }

    @Test("parentAgentScope returns existing tab scope")
    func parentAgentScopeReturnsExistingScope() throws {
        let projectID = UUID()
        let worktreeID = UUID()
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        let agentID = UUID()
        let agentArea = TabArea(
            projectPath: testPath,
            existingTab: TerminalTab(parentAgentState: ParentAgentTabState(
                id: agentID,
                projectID: projectID,
                worktreeID: worktreeID,
                projectPath: testPath
            ))
        )
        let agentTab = WorkspaceTab(root: .tabArea(agentArea), focusedAreaID: agentArea.id)
        let workspace = WorktreeWorkspace(tabs: [agentTab], activeTabID: agentTab.id)
        let appState = AppState(
            selectionStore: TestSelectionStore(),
            terminalViews: TestTerminalViewRemover(),
            workspacePersistence: TestWorkspacePersistence()
        )
        appState.activeProjectID = projectID
        appState.activeWorktreeID = [projectID: worktreeID]
        appState.activeWorktreePath = [projectID: testPath]
        appState.workspaces = [key: workspace]

        let scope = try #require(appState.parentAgentScope(projectID: projectID, worktreeID: worktreeID))

        #expect(scope.agentID == agentID)
        #expect(scope.projectID == projectID)
        #expect(scope.worktreeID == worktreeID)
        #expect(scope.projectPath == testPath)
    }
}

@MainActor
private final class TestSelectionStore: ActiveProjectSelectionStoring {
    var activeProjectID: UUID?
    var activeWorktreeIDs: [UUID: UUID] = [:]

    func loadActiveProjectID() -> UUID? {
        activeProjectID
    }

    func saveActiveProjectID(_ id: UUID?) {
        activeProjectID = id
    }

    func loadActiveWorktreeIDs() -> [UUID: UUID] {
        activeWorktreeIDs
    }

    func saveActiveWorktreeIDs(_ ids: [UUID: UUID]) {
        activeWorktreeIDs = ids
    }
}

@MainActor
private final class TestTerminalViewRemover: TerminalViewRemoving {
    func removeView(for paneID: UUID) {
        _ = paneID
    }

    func needsConfirmQuit(for paneID: UUID) -> Bool {
        _ = paneID
        return false
    }
}

private final class TestWorkspacePersistence: WorkspacePersisting {
    var snapshots: [WorkspaceSnapshot] = []

    func loadWorkspaces() throws -> [WorkspaceSnapshot] {
        snapshots
    }

    func saveWorkspaces(_ workspaces: [WorkspaceSnapshot]) throws {
        snapshots = workspaces
    }
}
