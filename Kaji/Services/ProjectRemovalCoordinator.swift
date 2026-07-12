import Foundation

struct ProjectRemovalImpact: Equatable {
    let hasUnsavedEditors: Bool
    let hasRunningTerminals: Bool
    let hasRunningAgents: Bool
    let hasCodeGraphSessions: Bool
    let worktreeCount: Int

    var hasRunningWork: Bool {
        hasRunningTerminals || hasRunningAgents || hasCodeGraphSessions
    }
}

@MainActor
enum ProjectRemovalCoordinator {
    static func impact(project: Project, appState: AppState, worktreeStore: WorktreeStore) -> ProjectRemovalImpact {
        let worktrees = worktreeStore.list(for: project.id)
        return ProjectRemovalImpact(
            hasUnsavedEditors: appState.hasUnsavedEditorTabs(projectID: project.id),
            hasRunningTerminals: appState.hasRunningTerminalProcesses(projectID: project.id),
            hasRunningAgents: AIActivityStore.shared.hasActiveAgent(projectID: project.id),
            hasCodeGraphSessions: worktrees.contains { KajiCodeGraphAgentCoordinator.shared.hasSession(projectID: project.id, worktreeID: $0.id) },
            worktreeCount: worktrees.count
        )
    }

    static func remove(
        project: Project,
        appState: AppState,
        projectStore: ProjectStore,
        worktreeStore: WorktreeStore,
        cleanupOnDisk: Bool = true
    ) async {
        let knownWorktrees = worktreeStore.list(for: project.id)
        let paths = ([project.path] + knownWorktrees.map(\.path)).filter { !$0.isEmpty }
        let metadataPaneIDs = appState.terminalPaneIDs(for: project.id) + appState.parentAgentIDs(for: project.id)
        let staleMessage = "Project was removed from Kaji."

        KajiAgentStoreRegistry.shared.stop(projectID: project.id)
        KajiCodeGraphAgentCoordinator.shared.close(projectID: project.id)
        KajiCodeGraphRuntime.shared.clear(projectID: project.id)
        AIActivityStore.shared.markProjectStale(projectID: project.id, message: staleMessage)
        CodingAgentSessionMetadataStore.shared.remove(paneIDs: metadataPaneIDs)
        NotificationStore.shared.remove(projectID: project.id)
        await FFFSearchService.removeIndexes(projectPaths: paths)

        appState.removeProject(project.id)
        projectStore.remove(id: project.id)
        worktreeStore.removeProject(project.id)

        guard cleanupOnDisk else { return }
        Task.detached {
            await WorktreeStore.cleanupOnDisk(for: project, knownWorktrees: knownWorktrees)
        }
    }
}
