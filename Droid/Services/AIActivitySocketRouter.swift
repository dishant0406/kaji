import Foundation

@MainActor
enum AIActivitySocketRouter {
    struct Payload {
        let type: String
        let title: String
        let body: String
        let paneIDString: String?
    }

    private struct RoutingContext {
        let appState: AppState?
        let worktreeStore: WorktreeStore?
    }

    private struct ExplicitContext {
        let projectID: UUID
        let worktreeID: UUID
        let worktreePath: String?
    }

    static func handle(_ payload: Payload, appState: AppState?, worktreeStore: WorktreeStore?) -> Bool {
        guard let paneIDString = payload.paneIDString, let paneID = UUID(uuidString: paneIDString) else {
            return false
        }

        if payload.type.hasSuffix("_transcript") {
            let providerID = String(payload.type.dropLast("_transcript".count))
            AIActivityStore.shared.appendTranscript(
                providerID: providerID,
                paneID: paneID,
                kind: payload.title,
                text: payload.body
            )
            return true
        }

        guard payload.type.hasSuffix("_activity") else { return false }
        let providerID = String(payload.type.dropLast("_activity".count))
        let context = explicitContext(from: payload.body)
        return handleProviderActivity(
            providerID: providerID,
            state: payload.title,
            paneID: paneID,
            explicitContext: context,
            routingContext: RoutingContext(appState: appState, worktreeStore: worktreeStore)
        )
    }

    private static func handleProviderActivity(
        providerID: String,
        state: String,
        paneID: UUID,
        explicitContext: ExplicitContext?,
        routingContext: RoutingContext
    ) -> Bool {
        let normalizedState = state.lowercased()
        if normalizedState == "stop" {
            if let explicitContext {
                AIActivityStore.shared.stop(
                    providerID: providerID,
                    projectID: explicitContext.projectID,
                    worktreeID: explicitContext.worktreeID
                )
            } else if let appState = routingContext.appState,
                      let worktreeStore = routingContext.worktreeStore,
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
                worktreeID: explicitContext.worktreeID,
                worktreePath: explicitContext.worktreePath
            )
            return true
        }
        guard let appState = routingContext.appState else { return true }
        AIActivityStore.shared.start(
            providerID: providerID,
            paneID: paneID,
            appState: appState,
            worktreeStore: routingContext.worktreeStore
        )
        return true
    }

    private static func explicitContext(from body: String) -> ExplicitContext? {
        let parts = body.split(separator: ",", maxSplits: 2).map(String.init)
        guard parts.count >= 2,
              let projectID = UUID(uuidString: parts[0]),
              let worktreeID = UUID(uuidString: parts[1])
        else {
            return nil
        }
        return ExplicitContext(projectID: projectID, worktreeID: worktreeID, worktreePath: parts.count == 3 ? parts[2] : nil)
    }
}
