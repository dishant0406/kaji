import Foundation
import Testing

@testable import Kaji

@Suite("AppState Diff Viewer")
@MainActor
struct AppStateDiffViewerTests {
    private let testPath = "/tmp/kaji-diff-test"

    @Test
    func openDiffViewerUsesSourceControlFileSnapshotWithoutShowingAllChanges() throws {
        let fixture = AppStateDiffViewerFixture(path: testPath)
        let file = GitStatusFile(
            path: "new.swift",
            oldPath: nil,
            xStatus: "?",
            yStatus: "?",
            additions: 4,
            deletions: 0,
            isBinary: false
        )
        let vcs = VCSTabState(projectPath: testPath, files: [file])

        fixture.appState.openDiffViewer(vcs: vcs, filePath: file.path, isStaged: false, projectID: fixture.projectID)

        let diffState = try fixture.activeDiffState()
        #expect(diffState.filePath == file.path)
        #expect(diffState.showsAllChanges == false)
        #expect(diffState.vcs.files == [file])
    }

    @Test
    func openDiffViewerReusesExistingFileDiffTab() throws {
        let fixture = AppStateDiffViewerFixture(path: testPath)
        let file = GitStatusFile(
            path: "changed.swift",
            oldPath: nil,
            xStatus: " ",
            yStatus: "M",
            additions: 2,
            deletions: 1,
            isBinary: false
        )
        let vcs = VCSTabState(projectPath: testPath, files: [file])

        fixture.appState.openDiffViewer(vcs: vcs, filePath: file.path, isStaged: false, projectID: fixture.projectID)
        let firstActiveTabID = try #require(fixture.workspace.activeTabID)
        fixture.appState.openDiffViewer(vcs: vcs, filePath: file.path, isStaged: false, projectID: fixture.projectID)

        #expect(fixture.workspace.tabs.count == 2)
        #expect(fixture.workspace.activeTabID == firstActiveTabID)
    }
}

@MainActor
private final class AppStateDiffViewerFixture {
    let projectID = UUID()
    let worktreeID = UUID()
    let appState: AppState
    let key: WorktreeKey

    init(path: String) {
        key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        let area = TabArea(projectPath: path)
        let workspaceTab = WorkspaceTab(root: .tabArea(area), focusedAreaID: area.id)
        appState = AppState(
            selectionStore: DiffViewerSelectionStore(),
            terminalViews: DiffViewerTerminalViews(),
            workspacePersistence: DiffViewerWorkspacePersistence()
        )
        appState.activeProjectID = projectID
        appState.activeWorktreeID = [projectID: worktreeID]
        appState.activeWorktreePath = [projectID: path]
        appState.workspaces = [key: WorktreeWorkspace(tabs: [workspaceTab], activeTabID: workspaceTab.id)]
        appState.workspaceRoots = [key: workspaceTab.root]
        appState.focusedAreaID = [key: area.id]
    }

    var workspace: WorktreeWorkspace {
        appState.workspaces[key]!
    }

    func activeDiffState() throws -> DiffViewerTabState {
        let activeTab = try #require(workspace.activeTab)
        let area = try #require(activeTab.root.allAreas().first)
        let tab = try #require(area.tabs.first)
        return try #require(tab.content.diffViewerState)
    }
}

private struct DiffViewerSelectionStore: ActiveProjectSelectionStoring {
    func loadActiveProjectID() -> UUID? { nil }
    func saveActiveProjectID(_: UUID?) {}
    func loadActiveWorktreeIDs() -> [UUID: UUID] { [:] }
    func saveActiveWorktreeIDs(_: [UUID: UUID]) {}
}

private struct DiffViewerTerminalViews: TerminalViewRemoving {
    func removeView(for _: UUID) {}
    func needsConfirmQuit(for _: UUID) -> Bool { false }
}

private struct DiffViewerWorkspacePersistence: WorkspacePersisting {
    func loadWorkspaces() throws -> [WorkspaceSnapshot] { [] }
    func saveWorkspaces(_: [WorkspaceSnapshot]) throws {}
}
