import Foundation

struct KajiAgentWorkspaceContext {
    let appState: AppState
    let project: Project
    let worktree: Worktree
}

@MainActor
enum KajiAgentWorkspaceContextResolver {
    static func active(
        appState: AppState?,
        projectStore: ProjectStore?,
        worktreeStore: WorktreeStore?
    ) -> KajiAgentWorkspaceContext? {
        guard let appState, let projectStore, let worktreeStore,
              let projectID = appState.activeProjectID,
              let project = projectStore.projects.first(where: { $0.id == projectID })
        else { return nil }
        worktreeStore.ensurePrimary(for: project)
        let worktree = appState.activeWorktreeKey(for: project.id)
            .flatMap { worktreeStore.worktree(projectID: project.id, worktreeID: $0.worktreeID) }
            ?? worktreeStore.primary(for: project.id)
            ?? Worktree(name: project.name, path: project.path, isPrimary: true)
        return KajiAgentWorkspaceContext(appState: appState, project: project, worktree: worktree)
    }
}
