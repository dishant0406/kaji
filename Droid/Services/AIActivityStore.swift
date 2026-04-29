import Foundation

@MainActor
@Observable
final class AIActivityStore {
    struct Activity: Equatable {
        let paneID: UUID
        let projectID: UUID
        let worktreeID: UUID
        let providerID: String
    }

    static let shared = AIActivityStore()

    private(set) var activitiesByPaneID: [UUID: Activity] = [:]

    private init() {}

    func hasActiveAgent(projectID: UUID) -> Bool {
        return activitiesByPaneID.values.contains { $0.projectID == projectID }
    }

    func start(
        providerID: String,
        paneID: UUID,
        appState: AppState,
        worktreeStore: WorktreeStore?
    ) {
        if let worktreeStore,
           let context = NotificationNavigator.resolveContext(
               for: paneID,
               appState: appState,
               worktreeStore: worktreeStore
           )
        {
            start(
                providerID: providerID,
                paneID: paneID,
                projectID: context.projectID,
                worktreeID: context.worktreeID
            )
            return
        }

        guard let projectID = appState.activeProjectID,
              let key = appState.activeWorktreeKey(for: projectID)
        else {
            return
        }

        start(
            providerID: providerID,
            paneID: paneID,
            projectID: key.projectID,
            worktreeID: key.worktreeID
        )
    }

    func start(
        providerID: String,
        paneID: UUID,
        projectID: UUID,
        worktreeID: UUID
    ) {
        stop(
            providerID: providerID,
            projectID: projectID,
            worktreeID: worktreeID
        )
        activitiesByPaneID[paneID] = Activity(
            paneID: paneID,
            projectID: projectID,
            worktreeID: worktreeID,
            providerID: providerID
        )
    }

    func stop(paneID: UUID) {
        activitiesByPaneID.removeValue(forKey: paneID)
    }

    func stop(
        providerID: String,
        projectID: UUID,
        worktreeID: UUID
    ) {
        activitiesByPaneID = activitiesByPaneID.filter { _, activity in
            !(activity.providerID == providerID &&
              activity.projectID == projectID &&
              activity.worktreeID == worktreeID)
        }
    }

    func stop(
        providerID: String,
        projectID: UUID
    ) {
        activitiesByPaneID = activitiesByPaneID.filter { _, activity in
            !(activity.providerID == providerID &&
              activity.projectID == projectID)
        }
    }

    func reset() {
        activitiesByPaneID.removeAll()
    }

    func pruneMissingPanes(appState: AppState) {
        let validPaneIDs = Set(
            appState.workspaces.values.flatMap { workspace in
                workspace.tabs.flatMap { workspaceTab in
                    workspaceTab.root.allAreas().flatMap { area in
                        area.tabs.compactMap { $0.content.pane?.id }
                    }
                }
            }
        )
        activitiesByPaneID = activitiesByPaneID.filter { validPaneIDs.contains($0.key) }
    }
}
