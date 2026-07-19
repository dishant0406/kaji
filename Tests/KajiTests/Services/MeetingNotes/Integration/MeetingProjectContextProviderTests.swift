import Foundation
import Testing

@testable import Kaji

@MainActor
@Suite("Meeting project context provider")
struct MeetingProjectContextProviderTests {
    @Test("all-project scope still obeys builder project and character bounds")
    func allProjectBounds() {
        let projects = (0 ..< 10).map { Project(name: "Project \($0)", path: "/tmp/project-\($0)") }
        let projectStore = ProjectStore(persistence: ContextProjectPersistence(projects: projects))
        let worktreeStore = WorktreeStore(
            persistence: ContextWorktreePersistence(),
            listRiftWorkspaces: { _ in [] },
            projects: projects
        )
        let appState = AppState(
            selectionStore: ContextSelectionStore(),
            terminalViews: ContextTerminalViews(),
            workspacePersistence: ContextWorkspacePersistence()
        )
        let provider = MeetingProjectContextProvider(
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore,
            agentRunStore: AgentRunStore(),
            builder: MeetingProjectContextBuilder(limits: MeetingProjectContextLimits(
                maximumProjects: 3,
                maximumFilesPerProject: 2,
                maximumTotalCharacters: 40,
                maximumNameLength: 20,
                maximumSummaryLength: 20,
                maximumRelativePathLength: 20
            ))
        )

        let context = provider.context(scope: .all, allowedProjectIDs: Set(projects.map(\.id)))

        #expect(context.projects.count == 3)
        #expect(context.totalCharacterCount <= 40)
        #expect(provider.projectIDs(scope: .all).count == 10)
    }
}

private struct ContextProjectPersistence: ProjectPersisting {
    let projects: [Project]

    func loadProjects() throws -> [Project] { projects }
    func saveProjects(_: [Project]) throws {}
}

private struct ContextWorktreePersistence: WorktreePersisting {
    func loadWorktrees(projectID _: UUID) throws -> [Worktree] { [] }
    func saveWorktrees(_: [Worktree], projectID _: UUID) throws {}
    func removeWorktrees(projectID _: UUID) throws {}
}

@MainActor
private final class ContextSelectionStore: ActiveProjectSelectionStoring {
    func loadActiveProjectID() -> UUID? { nil }
    func saveActiveProjectID(_: UUID?) {}
    func loadActiveWorktreeIDs() -> [UUID: UUID] { [:] }
    func saveActiveWorktreeIDs(_: [UUID: UUID]) {}
}

@MainActor
private final class ContextTerminalViews: TerminalViewRemoving {
    func removeView(for _: UUID) {}
    func needsConfirmQuit(for _: UUID) -> Bool { false }
}

private struct ContextWorkspacePersistence: WorkspacePersisting {
    func loadWorkspaces() throws -> [WorkspaceSnapshot] { [] }
    func saveWorkspaces(_: [WorkspaceSnapshot]) throws {}
}
