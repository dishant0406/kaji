import Foundation
import Testing

@testable import Kaji

@MainActor
struct NotificationFallbackContextResolverTests {
    @Test
    func prefersFocusedAreaActiveTabEvenWithoutTerminalPane() {
        let projectID = UUID()
        let worktreeID = UUID()
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        let path = "/tmp/project"

        let focusedArea = TabArea(projectPath: path)
        focusedArea.createEditorTab(filePath: "/tmp/project/README.md")

        let secondaryArea = TabArea(projectPath: path)
        let root = SplitNode.split(SplitBranch(
            direction: .horizontal,
            first: .tabArea(focusedArea),
            second: .tabArea(secondaryArea)
        ))

        let appState = AppState(
            selectionStore: StubSelectionStore(),
            terminalViews: StubTerminalViewRemoving(),
            workspacePersistence: StubWorkspacePersistence()
        )
        appState.activeProjectID = projectID
        appState.activeWorktreeID[projectID] = worktreeID
        appState.activeWorktreePath[projectID] = path
        appState.workspaceRoots[key] = root
        appState.focusedAreaID[key] = focusedArea.id

        let context = NotificationFallbackContextResolver.resolve(
            key: key,
            appState: appState,
            worktreeStore: nil
        )

        #expect(context?.areaID == focusedArea.id)
        #expect(context?.tabID == focusedArea.activeTabID)
    }
}

private struct StubSelectionStore: ActiveProjectSelectionStoring {
    func loadActiveProjectID() -> UUID? { nil }
    func saveActiveProjectID(_ id: UUID?) {}
    func loadActiveWorktreeIDs() -> [UUID: UUID] { [:] }
    func saveActiveWorktreeIDs(_ ids: [UUID: UUID]) {}
}

private struct StubTerminalViewRemoving: TerminalViewRemoving {
    func removeView(for paneID: UUID) {}
    func needsConfirmQuit(for paneID: UUID) -> Bool { false }
}

private struct StubWorkspacePersistence: WorkspacePersisting {
    func saveWorkspaces(_ workspaces: [WorkspaceSnapshot]) throws {}
    func loadWorkspaces() throws -> [WorkspaceSnapshot] { [] }
}
