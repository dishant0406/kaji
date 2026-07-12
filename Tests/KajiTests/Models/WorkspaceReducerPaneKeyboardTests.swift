import Foundation
import Testing

@testable import Kaji

@Suite("WorkspaceReducer pane keyboard actions")
@MainActor
struct WorkspaceReducerPaneKeyboardTests {
    private let testPath = "/tmp/test"

    @Test("focus next and previous pane cycle through layout order")
    func focusNextPreviousPane() {
        let fixture = makeThreePaneState()
        var state = fixture.state

        _ = WorkspaceReducer.reduce(action: .focusNextPane(projectID: fixture.projectID), state: &state)
        #expect(state.focusedAreaID[fixture.key] == fixture.second.id)

        _ = WorkspaceReducer.reduce(action: .focusPreviousPane(projectID: fixture.projectID), state: &state)
        #expect(state.focusedAreaID[fixture.key] == fixture.first.id)
    }

    @Test("focus pane by index selects matching layout pane")
    func focusPaneByIndex() {
        let fixture = makeThreePaneState()
        var state = fixture.state

        _ = WorkspaceReducer.reduce(action: .focusPaneByIndex(projectID: fixture.projectID, index: 2), state: &state)

        #expect(state.focusedAreaID[fixture.key] == fixture.third.id)
    }

    @Test("resize focused pane updates nearest matching split")
    func resizeFocusedPane() {
        let fixture = makeThreePaneState()
        var state = fixture.state

        _ = WorkspaceReducer.reduce(action: .resizeFocusedPane(projectID: fixture.projectID, command: .wider), state: &state)

        guard case let .split(branch)? = state.workspaceRoots[fixture.key] else {
            Issue.record("expected split root")
            return
        }
        #expect(branch.ratio == 0.55)
    }

    @Test("balance panes resets all split ratios")
    func balancePanes() {
        let fixture = makeThreePaneState(rootRatio: 0.7, nestedRatio: 0.3)
        var state = fixture.state

        _ = WorkspaceReducer.reduce(action: .balancePanes(projectID: fixture.projectID), state: &state)

        guard case let .split(root)? = state.workspaceRoots[fixture.key],
              case let .split(nested) = root.second else {
            Issue.record("expected nested split root")
            return
        }
        #expect(root.ratio == 0.5)
        #expect(nested.ratio == 0.5)
    }

    private func makeThreePaneState(
        rootRatio: CGFloat = 0.5,
        nestedRatio: CGFloat = 0.5
    ) -> (
        projectID: UUID,
        key: WorktreeKey,
        first: TabArea,
        second: TabArea,
        third: TabArea,
        state: WorkspaceState
    ) {
        let projectID = UUID()
        let worktreeID = UUID()
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        let first = TabArea(projectPath: testPath)
        let second = TabArea(projectPath: testPath)
        let third = TabArea(projectPath: testPath)
        let nested = SplitBranch(direction: .vertical, ratio: nestedRatio, first: .tabArea(second), second: .tabArea(third))
        let root = SplitBranch(direction: .horizontal, ratio: rootRatio, first: .tabArea(first), second: .split(nested))
        let tab = WorkspaceTab(root: .split(root), focusedAreaID: first.id)
        let workspace = WorktreeWorkspace(tabs: [tab], activeTabID: tab.id)
        let state = WorkspaceState(
            activeProjectID: projectID,
            activeWorktreeID: [projectID: worktreeID],
            activeWorktreePath: [projectID: testPath],
            workspaces: [key: workspace],
            workspaceRoots: [key: .split(root)],
            focusedAreaID: [key: first.id],
            focusHistory: [:]
        )
        return (projectID, key, first, second, third, state)
    }
}
