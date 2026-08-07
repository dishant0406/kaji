import Foundation
import Testing

@testable import Kaji

@Suite("ProjectRemovalCoordinator", .serialized)
@MainActor
struct ProjectRemovalCoordinatorTests {
    @Test("remove clears app state, stores, worktrees, and terminal views")
    func removeClearsProjectState() async throws {
        let project = Project(name: "Repo", path: "/tmp/repo")
        let primary = Worktree(name: "Repo", path: project.path, isPrimary: true)
        let secondary = Worktree(name: "Feature", path: "/tmp/repo-feature", isPrimary: false)
        let projectPersistence = ProjectRemovalProjectPersistence(projects: [project])
        let worktreePersistence = ProjectRemovalWorktreePersistence(worktrees: [project.id: [primary, secondary]])
        let projectStore = ProjectStore(persistence: projectPersistence)
        let worktreeStore = WorktreeStore(persistence: worktreePersistence, projects: [project])
        let terminalViews = ProjectRemovalTerminalViews()
        let appState = AppState(
            selectionStore: ProjectRemovalSelectionStore(),
            terminalViews: terminalViews,
            workspacePersistence: ProjectRemovalWorkspacePersistence()
        )
        let pane = TerminalPaneState(projectPath: project.path)
        let area = TabArea(projectPath: project.path, existingTab: TerminalTab(pane: pane))
        let workspaceTab = WorkspaceTab(root: .tabArea(area), focusedAreaID: area.id)
        let key = WorktreeKey(projectID: project.id, worktreeID: primary.id)
        appState.activeProjectID = project.id
        appState.activeWorktreeID[project.id] = primary.id
        appState.activeWorktreePath[project.id] = primary.path
        appState.workspaces[key] = WorktreeWorkspace(tabs: [workspaceTab], activeTabID: workspaceTab.id)
        appState.workspaceRoots[key] = workspaceTab.root
        appState.focusedAreaID[key] = area.id

        let service = ProjectRemovalService(
            tombstones: ProjectRemovalMemoryTombstones(),
            quiesceIndexes: { _ in },
            cleanupDisk: { _, _ in true }
        )
        _ = await service.removeManually(
            project: project,
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore,
            cleanupOnDisk: false
        )

        #expect(appState.activeProjectID == nil)
        #expect(appState.activeWorktreeID[project.id] == nil)
        #expect(appState.workspaces[key] == nil)
        #expect(projectStore.projects.isEmpty)
        #expect(worktreeStore.list(for: project.id).isEmpty)
        #expect(worktreePersistence.removedProjectIDs == [project.id])
        #expect(projectPersistence.savedProjects.last == [])
        #expect(terminalViews.removedPaneIDs == [pane.id])
    }

    @Test("impact reports project-scoped terminal and agent work")
    func impactReportsProjectWork() {
        let project = Project(name: "Repo", path: "/tmp/repo")
        let worktree = Worktree(name: "Repo", path: project.path, isPrimary: true)
        let worktreeStore = WorktreeStore(
            persistence: ProjectRemovalWorktreePersistence(worktrees: [project.id: [worktree]]),
            projects: [project]
        )
        let pane = TerminalPaneState(projectPath: project.path)
        let area = TabArea(projectPath: project.path, existingTab: TerminalTab(pane: pane))
        let workspaceTab = WorkspaceTab(root: .tabArea(area), focusedAreaID: area.id)
        let terminalViews = ProjectRemovalTerminalViews(runningPaneIDs: [pane.id])
        let appState = AppState(
            selectionStore: ProjectRemovalSelectionStore(),
            terminalViews: terminalViews,
            workspacePersistence: ProjectRemovalWorkspacePersistence()
        )
        let key = WorktreeKey(projectID: project.id, worktreeID: worktree.id)
        appState.activeProjectID = project.id
        appState.activeWorktreeID[project.id] = worktree.id
        appState.activeWorktreePath[project.id] = worktree.path
        appState.workspaces[key] = WorktreeWorkspace(tabs: [workspaceTab], activeTabID: workspaceTab.id)
        appState.workspaceRoots[key] = workspaceTab.root

        let agentPaneID = UUID()
        AIActivityStore.shared.start(
            providerID: "codex",
            paneID: agentPaneID,
            projectID: project.id,
            worktreeID: worktree.id,
            worktreePath: worktree.path
        )
        defer { AIActivityStore.shared.markStale(paneID: agentPaneID, message: "Test cleanup") }

        let impact = ProjectRemovalCoordinator.impact(project: project, appState: appState, worktreeStore: worktreeStore)

        #expect(impact.hasRunningTerminals)
        #expect(impact.hasRunningAgents)
        #expect(impact.hasRunningWork)
        #expect(impact.worktreeCount == 1)
    }
    @Test("double removal is idempotent and quiesces once")
    func doubleRemovalIsNoOp() async {
        let project = Project(name: "Repo", path: "/tmp/repo")
        let persistence = ProjectRemovalProjectPersistence(projects: [project])
        let projectStore = ProjectStore(persistence: persistence)
        let worktreeStore = WorktreeStore(
            persistence: ProjectRemovalWorktreePersistence(worktrees: [project.id: []]),
            projects: [project]
        )
        let appState = AppState(
            selectionStore: ProjectRemovalSelectionStore(),
            terminalViews: ProjectRemovalTerminalViews(),
            workspacePersistence: ProjectRemovalWorkspacePersistence()
        )
        let recorder = ProjectRemovalQuiesceRecorder()
        let service = ProjectRemovalService(
            tombstones: ProjectRemovalMemoryTombstones(),
            quiesceIndexes: { recorder.record($0) },
            cleanupDisk: { _, _ in true }
        )

        let first = await service.removeManually(
            project: project,
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore,
            cleanupOnDisk: false
        )
        let second = await service.removeManually(
            project: project,
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore,
            cleanupOnDisk: false
        )

        #expect(first == .removed)
        #expect(second == .alreadyRemoved)
        #expect(recorder.calls == [[project.path]])
        #expect(persistence.savedProjects.count == 1)
    }

    @Test("already-emptied finalization does not dispatch removal again")
    func alreadyEmptiedFinalizationIsNonReentrant() async {
        let project = Project(name: "Repo", path: "/tmp/repo")
        let projectStore = ProjectStore(persistence: ProjectRemovalProjectPersistence(projects: [project]))
        let worktreeStore = WorktreeStore(
            persistence: ProjectRemovalWorktreePersistence(worktrees: [project.id: []]),
            projects: [project]
        )
        let appState = AppState(
            selectionStore: ProjectRemovalSelectionStore(),
            terminalViews: ProjectRemovalTerminalViews(),
            workspacePersistence: ProjectRemovalWorkspacePersistence()
        )
        var callbackCount = 0
        appState.onProjectsEmptied = { _ in callbackCount += 1 }
        let service = ProjectRemovalService(
            tombstones: ProjectRemovalMemoryTombstones(),
            quiesceIndexes: { _ in },
            cleanupDisk: { _, _ in true }
        )

        _ = await service.finalizeAlreadyEmptied(
            project: project,
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore,
            cleanupOnDisk: false
        )

        #expect(callbackCount == 0)
        #expect(projectStore.projects.isEmpty)
    }

    @Test("removal selects the first remaining project deterministically")
    func removalSelectsReplacement() async {
        let first = Project(name: "First", path: "/tmp/first")
        let second = Project(name: "Second", path: "/tmp/second")
        let firstWorktree = Worktree(name: "First", path: first.path, isPrimary: true)
        let secondWorktree = Worktree(name: "Second", path: second.path, isPrimary: true)
        let projectStore = ProjectStore(persistence: ProjectRemovalProjectPersistence(projects: [first, second]))
        let worktreeStore = WorktreeStore(
            persistence: ProjectRemovalWorktreePersistence(worktrees: [
                first.id: [firstWorktree],
                second.id: [secondWorktree],
            ]),
            projects: [first, second]
        )
        let appState = AppState(
            selectionStore: ProjectRemovalSelectionStore(),
            terminalViews: ProjectRemovalTerminalViews(),
            workspacePersistence: ProjectRemovalWorkspacePersistence()
        )
        appState.activeProjectID = first.id
        let service = ProjectRemovalService(
            tombstones: ProjectRemovalMemoryTombstones(),
            quiesceIndexes: { _ in },
            cleanupDisk: { _, _ in true }
        )

        _ = await service.removeManually(
            project: first,
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore,
            cleanupOnDisk: false
        )

        #expect(appState.activeProjectID == second.id)
        #expect(appState.activeWorktreeID[second.id] == secondWorktree.id)
    }

    @Test("failed tombstone persistence leaves visible project state unchanged")
    func failedTombstoneDefersRemoval() async {
        let project = Project(name: "Repo", path: "/tmp/repo")
        let projectStore = ProjectStore(persistence: ProjectRemovalProjectPersistence(projects: [project]))
        let worktreeStore = WorktreeStore(
            persistence: ProjectRemovalWorktreePersistence(worktrees: [project.id: []]),
            projects: [project]
        )
        let appState = AppState(
            selectionStore: ProjectRemovalSelectionStore(),
            terminalViews: ProjectRemovalTerminalViews(),
            workspacePersistence: ProjectRemovalWorkspacePersistence()
        )
        let service = ProjectRemovalService(
            tombstones: ProjectRemovalMemoryTombstones(failSaves: true),
            quiesceIndexes: { _ in },
            cleanupDisk: { _, _ in true }
        )

        let outcome = await service.removeManually(
            project: project,
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore
        )

        #expect(outcome == .deferred)
        #expect(projectStore.projects == [project])
    }

    @Test("persisted tombstone resumes interrupted removal")
    func recoveryCompletesRemoval() async {
        let project = Project(name: "Repo", path: "/tmp/repo")
        let worktree = Worktree(name: "Repo", path: project.path, isPrimary: true)
        let projectStore = ProjectStore(persistence: ProjectRemovalProjectPersistence(projects: [project]))
        let worktreeStore = WorktreeStore(
            persistence: ProjectRemovalWorktreePersistence(worktrees: [project.id: [worktree]]),
            projects: [project]
        )
        let appState = AppState(
            selectionStore: ProjectRemovalSelectionStore(),
            terminalViews: ProjectRemovalTerminalViews(),
            workspacePersistence: ProjectRemovalWorkspacePersistence()
        )
        let tombstones = ProjectRemovalMemoryTombstones(records: [
            ProjectRemovalTombstone(project: project, worktrees: [worktree], cleanupOnDisk: false),
        ])
        let service = ProjectRemovalService(
            tombstones: tombstones,
            quiesceIndexes: { _ in },
            cleanupDisk: { _, _ in true }
        )

        await service.recoverPendingRemovals(
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore
        )

        #expect(projectStore.projects.isEmpty)
        #expect(worktreeStore.list(for: project.id).isEmpty)
        #expect(tombstones.records.isEmpty)
    }
}

@Suite("Project removal cleanup helpers")
@MainActor
struct ProjectRemovalCleanupHelperTests {
    @Test("agent runs for removed project are marked stale")
    func agentRunsForRemovedProjectAreMarkedStale() {
        let store = AgentRunStore()
        let projectID = UUID()
        store.start(providerID: "codex", paneID: UUID(), projectID: projectID, worktreeID: UUID())

        store.markProjectStale(projectID: projectID, message: "Project removed")

        #expect(store.runs.first?.status == .stale)
        #expect(store.runs.first?.events.last?.text == "Project removed")
    }

    @Test("footer terminal store exposes retained project IDs")
    func footerTerminalStoreExposesProjectIDs() {
        let store = FooterTerminalStateStore()
        let visibleID = UUID()
        let retainedID = UUID()
        _ = store.show(projectID: visibleID, projectPath: "/tmp/visible")
        _ = store.show(projectID: retainedID, projectPath: "/tmp/retained")
        store.collapse(projectID: retainedID)

        #expect(store.projectIDs == [visibleID, retainedID])
    }
}

private enum ProjectRemovalTestError: Error {
    case saveFailed
}

private final class ProjectRemovalMemoryTombstones: ProjectRemovalTombstonePersisting {
    var records: [ProjectRemovalTombstone]
    let failSaves: Bool
    var quarantined = false

    init(records: [ProjectRemovalTombstone] = [], failSaves: Bool = false) {
        self.records = records
        self.failSaves = failSaves
    }

    func load() throws -> [ProjectRemovalTombstone] {
        records
    }

    func save(_ tombstones: [ProjectRemovalTombstone]) throws {
        if failSaves { throw ProjectRemovalTestError.saveFailed }
        records = tombstones
    }

    func quarantine() throws {
        quarantined = true
        records.removeAll()
    }
}

private final class ProjectRemovalQuiesceRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedCalls: [[String]] = []

    var calls: [[String]] {
        lock.withLock { recordedCalls }
    }

    func record(_ paths: [String]) {
        lock.withLock { recordedCalls.append(paths) }
    }
}

private final class ProjectRemovalProjectPersistence: ProjectPersisting {
    var projects: [Project]
    var savedProjects: [[Project]] = []

    init(projects: [Project]) {
        self.projects = projects
    }

    func loadProjects() throws -> [Project] {
        projects
    }

    func saveProjects(_ projects: [Project]) throws {
        savedProjects.append(projects)
        self.projects = projects
    }
}

private final class ProjectRemovalWorktreePersistence: WorktreePersisting {
    var worktrees: [UUID: [Worktree]]
    var removedProjectIDs: [UUID] = []

    init(worktrees: [UUID: [Worktree]]) {
        self.worktrees = worktrees
    }

    func loadWorktrees(projectID: UUID) throws -> [Worktree] {
        worktrees[projectID] ?? []
    }

    func saveWorktrees(_ worktrees: [Worktree], projectID: UUID) throws {
        self.worktrees[projectID] = worktrees
    }

    func removeWorktrees(projectID: UUID) throws {
        removedProjectIDs.append(projectID)
        worktrees.removeValue(forKey: projectID)
    }
}

private final class ProjectRemovalSelectionStore: ActiveProjectSelectionStoring {
    func loadActiveProjectID() -> UUID? { nil }
    func saveActiveProjectID(_: UUID?) {}
    func loadActiveWorktreeIDs() -> [UUID: UUID] { [:] }
    func saveActiveWorktreeIDs(_: [UUID: UUID]) {}
}

private final class ProjectRemovalTerminalViews: TerminalViewRemoving {
    var removedPaneIDs: [UUID] = []
    let runningPaneIDs: Set<UUID>

    init(runningPaneIDs: Set<UUID> = []) {
        self.runningPaneIDs = runningPaneIDs
    }

    func removeView(for paneID: UUID) {
        removedPaneIDs.append(paneID)
    }

    func needsConfirmQuit(for paneID: UUID) -> Bool {
        runningPaneIDs.contains(paneID)
    }
}

private final class ProjectRemovalWorkspacePersistence: WorkspacePersisting {
    var savedWorkspaces: [[WorkspaceSnapshot]] = []

    func loadWorkspaces() throws -> [WorkspaceSnapshot] { [] }

    func saveWorkspaces(_ workspaces: [WorkspaceSnapshot]) throws {
        savedWorkspaces.append(workspaces)
    }
}
