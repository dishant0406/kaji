import Foundation

@MainActor
enum AIActivitySocketRouter {
    struct Payload {
        let type: String
        let title: String
        let body: String
        let paneIDString: String?
    }

    static func handle(_ payload: Payload, appState: AppState?, worktreeStore: WorktreeStore?) -> Bool {
        guard let paneIDString = payload.paneIDString, let paneID = UUID(uuidString: paneIDString) else {
            return false
        }

        guard payload.type.hasSuffix("_activity") else { return false }
        let providerID = String(payload.type.dropLast("_activity".count))
        let context = explicitContext(from: payload.body)
        return handleProviderActivity(
            providerID: providerID,
            state: payload.title,
            paneID: paneID,
            explicitContext: context,
            appState: appState,
            worktreeStore: worktreeStore
        )
    }

    private static func handleProviderActivity(
        providerID: String,
        state: String,
        paneID: UUID,
        explicitContext: (projectID: UUID, worktreeID: UUID)?,
        appState: AppState?,
        worktreeStore: WorktreeStore?
    ) -> Bool {
        let normalizedState = state.lowercased()
        if normalizedState == "stop" {
            if let explicitContext {
                AIActivityStore.shared.stop(
                    providerID: providerID,
                    projectID: explicitContext.projectID,
                    worktreeID: explicitContext.worktreeID
                )
            } else if let appState,
               let worktreeStore,
               let context = NotificationNavigator.resolveContext(
                   for: paneID,
                   appState: appState,
                   worktreeStore: worktreeStore
               )
            {
                AIActivityStore.shared.stop(
                    providerID: providerID,
                    projectID: context.projectID,
                    worktreeID: context.worktreeID
                )
            }
            AIActivityStore.shared.stop(paneID: paneID)
            return true
        }

        guard normalizedState == "start" else { return true }
        if let explicitContext {
            AIActivityStore.shared.start(
                providerID: providerID,
                paneID: paneID,
                projectID: explicitContext.projectID,
                worktreeID: explicitContext.worktreeID
            )
            return true
        }
        guard let appState else { return true }
        AIActivityStore.shared.start(
            providerID: providerID,
            paneID: paneID,
            appState: appState,
            worktreeStore: worktreeStore
        )
        return true
    }

    private static func explicitContext(from body: String) -> (projectID: UUID, worktreeID: UUID)? {
        let parts = body.split(separator: ",", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let projectID = UUID(uuidString: parts[0]),
              let worktreeID = UUID(uuidString: parts[1])
        else {
            return nil
        }
        return (projectID, worktreeID)
    }
}
