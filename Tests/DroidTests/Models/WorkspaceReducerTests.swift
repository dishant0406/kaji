import Foundation
import Testing

@testable import Droid

@Suite("WorkspaceReducer")
@MainActor
struct WorkspaceReducerTests {
    private let testPath = "/tmp/test"

    private func makeState(projectID: UUID, worktreeID: UUID) -> WorkspaceState {
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        let area = TabArea(projectPath: testPath)
        let tab = WorkspaceTab(root: SplitNode.tabArea(area), focusedAreaID: area.id)
        let workspace = WorktreeWorkspace(tabs: [tab], activeTabID: tab.id)
        return WorkspaceState(
            activeProjectID: projectID,
            activeWorktreeID: [projectID: worktreeID],
            activeWorktreePath: [projectID: testPath],
            workspaces: [key: workspace],
            workspaceRoots: [key: .tabArea(area)],
            focusedAreaID: [key: area.id],
            focusHistory: [:]
        )
    }

    @Test("createTab appends a new workspace tab")
    func createTab() {
        let projectID = UUID()
        let worktreeID = UUID()
        var state = makeState(projectID: projectID, worktreeID: worktreeID)
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)

        _ = WorkspaceReducer.reduce(
            action: .createTab(projectID: projectID, areaID: nil),
            state: &state
        )

        let workspace = state.workspaces[key]
        #expect(workspace?.tabs.count == 2)
        #expect(workspace?.activeTab?.root.allAreas().count == 1)
    }

    @Test("createTab bootstraps an empty workspace")
    func createTabFromEmptySelection() {
        let projectID = UUID()
        let worktreeID = UUID()
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        var state = WorkspaceState(
            activeProjectID: projectID,
            activeWorktreeID: [projectID: worktreeID],
            activeWorktreePath: [projectID: testPath],
            workspaces: [:],
            workspaceRoots: [:],
            focusedAreaID: [:],
            focusHistory: [:]
        )

        _ = WorkspaceReducer.reduce(
            action: .createTab(projectID: projectID, areaID: nil),
            state: &state
        )

        #expect(state.workspaces[key]?.tabs.count == 1)
        #expect(state.workspaceRoots[key]?.allAreas().count == 1)
    }

    @Test("createCommandSplit adds a pane to the active workspace tab")
    func createCommandSplit() {
        let projectID = UUID()
        let worktreeID = UUID()
        var state = makeState(projectID: projectID, worktreeID: worktreeID)
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)

        _ = WorkspaceReducer.reduce(
            action: .createCommandSplit(projectID: projectID, title: "Codex", command: "pwd"),
            state: &state
        )

        #expect(state.workspaces[key]?.tabs.count == 1)
        #expect(state.workspaceRoots[key]?.allAreas().count == 2)
    }

    @Test("splitArea only mutates the active workspace tab")
    func splitAreaIsIsolatedToActiveWorkspaceTab() throws {
        let projectID = UUID()
        let worktreeID = UUID()
        var state = makeState(projectID: projectID, worktreeID: worktreeID)
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        let firstTabID = state.workspaces[key]!.activeTabID!
        let firstRootID = state.workspaces[key]!.activeTab!.root.id

        _ = WorkspaceReducer.reduce(
            action: .createTab(projectID: projectID, areaID: nil),
            state: &state
        )

        _ = WorkspaceReducer.reduce(
            action: .splitArea(.init(
                projectID: projectID,
                areaID: state.focusedAreaID[key]!,
                direction: .horizontal,
                position: .second
            )),
            state: &state
        )

        let workspace = try #require(state.workspaces[key])
        let originalTab = try #require(workspace.tabs.first(where: { $0.id == firstTabID }))
        let splitTab = try #require(workspace.activeTab)

        #expect(originalTab.root.id == firstRootID)
        #expect(originalTab.root.allAreas().count == 1)
        #expect(splitTab.root.allAreas().count == 2)
    }

    @Test("movePane rearranges split panes without creating workspace tabs")
    func movePaneRearrangesPanes() throws {
        let projectID = UUID()
        let worktreeID = UUID()
        var state = makeState(projectID: projectID, worktreeID: worktreeID)
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        let firstAreaID = try #require(state.focusedAreaID[key])

        _ = WorkspaceReducer.reduce(
            action: .splitArea(.init(
                projectID: projectID,
                areaID: firstAreaID,
                direction: .horizontal,
                position: .second
            )),
            state: &state
        )

        let secondAreaID = try #require(state.focusedAreaID[key])
        _ = WorkspaceReducer.reduce(
            action: .movePane(
                projectID: projectID,
                request: PaneMoveRequest(
                    sourceAreaID: secondAreaID,
                    targetAreaID: firstAreaID,
                    split: SplitPlacement(direction: .vertical, position: .first)
                )
            ),
            state: &state
        )

        let workspace = try #require(state.workspaces[key])
        let activeTab = try #require(workspace.activeTab)
        let root = activeTab.root
        guard case let .split(branch) = root else {
            Issue.record("expected split root after pane move")
            return
        }

        #expect(workspace.tabs.count == 1)
        #expect(root.allAreas().count == 2)
        #expect(branch.direction == .vertical)
        #expect(branch.first.findArea(id: secondAreaID) != nil)
        #expect(branch.second.findArea(id: firstAreaID) != nil)
    }

    @Test("closeArea collapses a split back to the remaining pane")
    func closeAreaCollapsesSplit() throws {
        let projectID = UUID()
        let worktreeID = UUID()
        var state = makeState(projectID: projectID, worktreeID: worktreeID)
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        let firstAreaID = try #require(state.focusedAreaID[key])

        _ = WorkspaceReducer.reduce(
            action: .splitArea(.init(
                projectID: projectID,
                areaID: firstAreaID,
                direction: .horizontal,
                position: .second
            )),
            state: &state
        )

        let secondAreaID = try #require(state.focusedAreaID[key])
        _ = WorkspaceReducer.reduce(
            action: .closeArea(projectID: projectID, areaID: secondAreaID),
            state: &state
        )

        let root = try #require(state.workspaceRoots[key])
        #expect(root.allAreas().count == 1)
        #expect(root.findArea(id: firstAreaID) != nil)
    }

    @Test("selectNextTab cycles top-level workspace tabs")
    func selectNextTab() {
        let projectID = UUID()
        let worktreeID = UUID()
        var state = makeState(projectID: projectID, worktreeID: worktreeID)
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)

        _ = WorkspaceReducer.reduce(action: .createTab(projectID: projectID, areaID: nil), state: &state)
        let firstActive = state.workspaces[key]?.activeTabID

        _ = WorkspaceReducer.reduce(action: .selectPreviousTab(projectID: projectID), state: &state)

        #expect(state.workspaces[key]?.activeTabID != firstActive)
    }

    @Test("closeTab removes a workspace tab and clears the workspace when last")
    func closeTab() {
        let projectID = UUID()
        let worktreeID = UUID()
        var state = makeState(projectID: projectID, worktreeID: worktreeID)
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        let firstTabID = state.workspaces[key]!.activeTabID!

        _ = WorkspaceReducer.reduce(action: .createTab(projectID: projectID, areaID: nil), state: &state)
        let effects = WorkspaceReducer.reduce(
            action: .closeTab(projectID: projectID, areaID: state.focusedAreaID[key]!, tabID: firstTabID),
            state: &state
        )

        #expect(state.workspaces[key]?.tabs.count == 1)
        #expect(!effects.paneIDsToRemove.isEmpty)

        let remainingTabID = state.workspaces[key]!.activeTabID!
        let finalEffects = WorkspaceReducer.reduce(
            action: .closeTab(projectID: projectID, areaID: state.focusedAreaID[key]!, tabID: remainingTabID),
            state: &state
        )

        #expect(state.workspaces[key] == nil)
        #expect(state.workspaceRoots[key] == nil)
        #expect(!finalEffects.projectIDsToRemove.isEmpty)
    }

    @Test("focusArea is isolated to the active workspace tab")
    func focusAreaIsolation() {
        let projectID = UUID()
        let worktreeID = UUID()
        var state = makeState(projectID: projectID, worktreeID: worktreeID)
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        let firstTabID = state.workspaces[key]!.activeTabID!

        _ = WorkspaceReducer.reduce(
            action: .splitArea(.init(
                projectID: projectID,
                areaID: state.focusedAreaID[key]!,
                direction: .horizontal,
                position: .second
            )),
            state: &state
        )
        let splitAreaID = state.focusedAreaID[key]!

        _ = WorkspaceReducer.reduce(action: .createTab(projectID: projectID, areaID: nil), state: &state)
        _ = WorkspaceReducer.reduce(action: .selectTab(projectID: projectID, areaID: splitAreaID, tabID: firstTabID), state: &state)

        #expect(state.focusedAreaID[key] == splitAreaID)
    }

    @Test("createEditorTab opens a top-level workspace tab")
    func createEditorTabCreatesWorkspaceTab() throws {
        let projectID = UUID()
        let worktreeID = UUID()
        var state = makeState(projectID: projectID, worktreeID: worktreeID)
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)

        _ = WorkspaceReducer.reduce(
            action: .createEditorTab(projectID: projectID, areaID: nil, filePath: "/tmp/test/file.swift"),
            state: &state
        )

        let workspace = try #require(state.workspaces[key])
        let activeTab = try #require(workspace.activeTab)

        #expect(workspace.tabs.count == 2)
        #expect(activeTab.root.allAreas().count == 1)
        #expect(activeTab.activeContent?.kind == .editor)
    }
}
