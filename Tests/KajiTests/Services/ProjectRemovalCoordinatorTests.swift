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

        await ProjectRemovalCoordinator.remove(
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
