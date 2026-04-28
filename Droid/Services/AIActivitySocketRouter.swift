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
        return handleProviderActivity(
            providerID: providerID,
            state: payload.title,
            paneID: paneID,
            appState: appState,
            worktreeStore: worktreeStore
        )
    }

    private static func handleProviderActivity(
        providerID: String,
        state: String,
        paneID: UUID,
        appState: AppState?,
        worktreeStore: WorktreeStore?
    ) -> Bool {
        let normalizedState = state.lowercased()
        if normalizedState == "stop" {
            AIActivityStore.shared.stop(paneID: paneID)
            return true
        }

        guard normalizedState == "start", let appState else { return true }
        AIActivityStore.shared.start(
            providerID: providerID,
            paneID: paneID,
            appState: appState,
            worktreeStore: worktreeStore
        )
        return true
    }
}
