import Foundation
import Testing

@testable import Kaji

@Suite("WorkspaceReducer pane swap")
@MainActor
struct WorkspaceReducerPaneSwapTests {
    private let testPath = "/tmp/test"

    @Test("swapPanes exchanges pane positions inside active workspace tab")
    func swapPanesExchangesPanePositionsInsideActiveWorkspaceTab() {
        let projectID = UUID()
        let worktreeID = UUID()
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        let first = TabArea(projectPath: testPath)
        let second = TabArea(projectPath: testPath)
        let branch = SplitBranch(direction: .horizontal, first: .tabArea(first), second: .tabArea(second))
        let tab = WorkspaceTab(root: .split(branch), focusedAreaID: first.id)
        let workspace = WorktreeWorkspace(tabs: [tab], activeTabID: tab.id)
        var state = WorkspaceState(
            activeProjectID: projectID,
            activeWorktreeID: [projectID: worktreeID],
            activeWorktreePath: [projectID: testPath],
            workspaces: [key: workspace],
            workspaceRoots: [key: .split(branch)],
            focusedAreaID: [key: first.id],
            focusHistory: [:]
        )

        _ = WorkspaceReducer.reduce(
            action: .swapPanes(projectID: projectID, sourceAreaID: first.id, targetAreaID: second.id),
            state: &state
        )

        guard case let .split(updatedBranch)? = state.workspaceRoots[key] else {
            Issue.record("expected split root")
            return
        }

        #expect(updatedBranch.first.id == second.id)
        #expect(updatedBranch.second.id == first.id)
        #expect(state.workspaces[key]?.activeTab?.root.allAreas().map(\.id) == [second.id, first.id])
        #expect(state.focusedAreaID[key] == first.id)
    }

    @Test("swapPanes exchanges nested leaves across different branches")
    func swapPanesExchangesNestedLeavesAcrossDifferentBranches() {
        let projectID = UUID()
        let worktreeID = UUID()
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        let first = TabArea(projectPath: testPath)
        let second = TabArea(projectPath: testPath)
        let third = TabArea(projectPath: testPath)
        let nested = SplitBranch(direction: .vertical, first: .tabArea(second), second: .tabArea(third))
        let rootBranch = SplitBranch(direction: .horizontal, first: .tabArea(first), second: .split(nested))
        let tab = WorkspaceTab(root: .split(rootBranch), focusedAreaID: first.id)
        let workspace = WorktreeWorkspace(tabs: [tab], activeTabID: tab.id)
        var state = WorkspaceState(
            activeProjectID: projectID,
            activeWorktreeID: [projectID: worktreeID],
            activeWorktreePath: [projectID: testPath],
            workspaces: [key: workspace],
            workspaceRoots: [key: .split(rootBranch)],
            focusedAreaID: [key: first.id],
            focusHistory: [:]
        )

        _ = WorkspaceReducer.reduce(
            action: .swapPanes(projectID: projectID, sourceAreaID: first.id, targetAreaID: third.id),
            state: &state
        )

        guard case let .split(updatedRoot)? = state.workspaceRoots[key],
              case let .split(updatedNested) = updatedRoot.second else {
            Issue.record("expected nested split root")
            return
        }

        #expect(updatedRoot.first.id == third.id)
        #expect(updatedNested.first.id == second.id)
        #expect(updatedNested.second.id == first.id)
        #expect(state.workspaces[key]?.activeTab?.root.allAreas().map(\.id) == [third.id, second.id, first.id])
        #expect(state.focusedAreaID[key] == first.id)
    }
}
