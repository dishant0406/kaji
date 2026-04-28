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
        activitiesByPaneID.values.contains { $0.projectID == projectID }
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
            activitiesByPaneID[paneID] = Activity(
                paneID: paneID,
                projectID: context.projectID,
                worktreeID: context.worktreeID,
                providerID: providerID
            )
            return
        }

        guard let projectID = appState.activeProjectID,
              let key = appState.activeWorktreeKey(for: projectID)
        else {
            return
        }

        activitiesByPaneID[paneID] = Activity(
            paneID: paneID,
            projectID: key.projectID,
            worktreeID: key.worktreeID,
            providerID: providerID
        )
    }

    func stop(paneID: UUID) {
        activitiesByPaneID.removeValue(forKey: paneID)
    }
}
