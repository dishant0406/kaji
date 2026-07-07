import Foundation
import Testing

@testable import Kaji

@Suite("Project selection service")
@MainActor
struct ProjectSelectionServiceTests {
    @Test("adds missing directory as project and selects it")
    func addsMissingDirectoryAsProject() throws {
        let fixture = try ProjectSelectionFixture()
        defer { fixture.cleanup() }
        let projectURL = try fixture.makeDirectory("NewProject")

        let result = try ProjectSelectionService.selectOrAddProject(
            path: projectURL.path,
            appState: fixture.appState,
            projectStore: fixture.projectStore,
            worktreeStore: fixture.worktreeStore
        )

        #expect(result.addedProject)
        #expect(fixture.projectStore.projects.count == 1)
        #expect(fixture.appState.activeProjectID == result.projectID)
        #expect(fixture.appState.activeWorktreeID[result.projectID] == result.worktreeID)
        #expect(fixture.projectStore.projects.first?.path == projectURL.path)
    }

    @Test("selects existing project without duplicating")
    func selectsExistingProjectWithoutDuplicating() throws {
        let fixture = try ProjectSelectionFixture()
        defer { fixture.cleanup() }
        let projectURL = try fixture.makeDirectory("Existing")
        let first = try ProjectSelectionService.selectOrAddProject(
            path: projectURL.path,
            appState: fixture.appState,
            projectStore: fixture.projectStore,
            worktreeStore: fixture.worktreeStore
        )

        let second = try ProjectSelectionService.selectOrAddProject(
            path: projectURL.appendingPathComponent(".").path,
            appState: fixture.appState,
            projectStore: fixture.projectStore,
            worktreeStore: fixture.worktreeStore
        )

        #expect(!second.addedProject)
        #expect(first.projectID == second.projectID)
        #expect(fixture.projectStore.projects.count == 1)
    }

    @Test("selects existing worktree matching path")
    func selectsExistingWorktreeMatchingPath() throws {
        let fixture = try ProjectSelectionFixture()
        defer { fixture.cleanup() }
        let projectURL = try fixture.makeDirectory("Repo")
        let worktreeURL = try fixture.makeDirectory("RepoWorktree")
        _ = try ProjectSelectionService.selectOrAddProject(
            path: projectURL.path,
            appState: fixture.appState,
            projectStore: fixture.projectStore,
            worktreeStore: fixture.worktreeStore
        )
        let project = try #require(fixture.projectStore.projects.first)
        let worktree = Worktree(name: "Feature", path: worktreeURL.path, source: .external, isPrimary: false)
        fixture.worktreeStore.add(worktree, to: project.id)

        let result = try ProjectSelectionService.selectOrAddProject(
            path: worktreeURL.path,
            appState: fixture.appState,
            projectStore: fixture.projectStore,
            worktreeStore: fixture.worktreeStore
        )

        #expect(!result.addedProject)
        #expect(result.projectID == project.id)
        #expect(result.worktreeID == worktree.id)
        #expect(fixture.appState.activeWorktreeID[project.id] == worktree.id)
    }

    @Test("preserves significant path whitespace")
    func preservesSignificantPathWhitespace() throws {
        let fixture = try ProjectSelectionFixture()
        defer { fixture.cleanup() }
        let projectURL = try fixture.makeDirectory("Trailing ")

        let result = try ProjectSelectionService.selectOrAddProject(
            path: projectURL.path,
            appState: fixture.appState,
            projectStore: fixture.projectStore,
            worktreeStore: fixture.worktreeStore
        )

        #expect(result.addedProject)
        #expect(fixture.projectStore.projects.first?.path == projectURL.path)
    }

    @Test("rejects missing directories")
    func rejectsMissingDirectories() throws {
        let fixture = try ProjectSelectionFixture()
        defer { fixture.cleanup() }
        let missing = fixture.root.appendingPathComponent("Missing")

        #expect(throws: ProjectSelectionServiceError.directoryNotFound(missing.path)) {
            _ = try ProjectSelectionService.selectOrAddProject(
                path: missing.path,
                appState: fixture.appState,
                projectStore: fixture.projectStore,
                worktreeStore: fixture.worktreeStore
            )
        }
    }
}

@MainActor
private final class ProjectSelectionFixture {
    let root: URL
    let projectStore: ProjectStore
    let worktreeStore: WorktreeStore
    let appState: AppState

    init() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("kaji-project-selection-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        projectStore = ProjectStore(persistence: MemoryProjectPersistence())
        worktreeStore = WorktreeStore(persistence: MemoryWorktreePersistence())
        appState = AppState(
            selectionStore: MemorySelectionStore(),
            terminalViews: MemoryTerminalViews(),
            workspacePersistence: MemoryWorkspacePersistence()
        )
    }

    func makeDirectory(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class MemoryProjectPersistence: ProjectPersisting {
    var projects: [Project] = []

    func loadProjects() throws -> [Project] { projects }
    func saveProjects(_ projects: [Project]) throws { self.projects = projects }
}

private final class MemoryWorktreePersistence: WorktreePersisting {
    var worktrees: [UUID: [Worktree]] = [:]

    func loadWorktrees(projectID: UUID) throws -> [Worktree] { worktrees[projectID] ?? [] }
    func saveWorktrees(_ worktrees: [Worktree], projectID: UUID) throws { self.worktrees[projectID] = worktrees }
    func removeWorktrees(projectID: UUID) throws { worktrees.removeValue(forKey: projectID) }
}

@MainActor
private final class MemorySelectionStore: ActiveProjectSelectionStoring {
    var projectID: UUID?
    var worktreeIDs: [UUID: UUID] = [:]

    func loadActiveProjectID() -> UUID? { projectID }
    func saveActiveProjectID(_ id: UUID?) { projectID = id }
    func loadActiveWorktreeIDs() -> [UUID: UUID] { worktreeIDs }
    func saveActiveWorktreeIDs(_ ids: [UUID: UUID]) { worktreeIDs = ids }
}

private struct MemoryTerminalViews: TerminalViewRemoving {
    func removeView(for paneID: UUID) {}
    func needsConfirmQuit(for paneID: UUID) -> Bool { false }
}

private final class MemoryWorkspacePersistence: WorkspacePersisting {
    var snapshots: [WorkspaceSnapshot] = []

    func loadWorkspaces() throws -> [WorkspaceSnapshot] { snapshots }
    func saveWorkspaces(_ workspaces: [WorkspaceSnapshot]) throws { snapshots = workspaces }
}
