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

    private struct ActivityContext {
        let explicitContext: ExplicitContext?
        let sessionID: String?
        let turnID: String?

        var hasRoutingContext: Bool { explicitContext != nil }
        var hasIdentity: Bool { sessionID != nil || turnID != nil }
    }

    private struct ActivityEventBody: Decodable {
        let projectID: UUID?
        let worktreeID: UUID?
        let worktreePath: String?
        let sessionID: String?
        let turnID: String?
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

        if payload.type.hasSuffix("_attention") {
            let providerID = String(payload.type.dropLast("_attention".count))
            AIActivityStore.shared.recordAttention(
                providerID: providerID,
                paneID: paneID,
                kind: payload.title,
                text: payload.body
            )
            return true
        }

        if payload.type.hasSuffix("_session") {
            let providerID = String(payload.type.dropLast("_session".count))
            return handleProviderSession(providerID: providerID, paneID: paneID, body: payload.body)
        }

        guard payload.type.hasSuffix("_activity") else { return false }
        let providerID = String(payload.type.dropLast("_activity".count))
        let context = activityContext(from: payload.body)
        return handleProviderActivity(
            providerID: providerID,
            state: payload.title,
            paneID: paneID,
            activityContext: context,
            routingContext: RoutingContext(appState: appState, worktreeStore: worktreeStore)
        )
    }

    private static func handleProviderActivity(
        providerID: String,
        state: String,
        paneID: UUID,
        activityContext: ActivityContext,
        routingContext: RoutingContext
    ) -> Bool {
        let normalizedState = state.lowercased()
        if normalizedState == "stop" {
            if AIActivityStore.shared.stop(paneID: paneID, sessionID: activityContext.sessionID, turnID: activityContext.turnID) != nil {
                return true
            }
            if let explicitContext = activityContext.explicitContext, !activityContext.hasIdentity {
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
            return true
        }

        if normalizedState == "observe" {
            AIActivityStore.shared.observe(
                providerID: providerID,
                paneID: paneID,
                sessionID: activityContext.sessionID,
                turnID: activityContext.turnID
            )
            return true
        }

        guard normalizedState == "start" else { return true }
        if let explicitContext = activityContext.explicitContext {
            AIActivityStore.shared.start(
                providerID: providerID,
                paneID: paneID,
                projectID: explicitContext.projectID,
                worktreeID: explicitContext.worktreeID,
                worktreePath: explicitContext.worktreePath,
                sessionID: activityContext.sessionID,
                turnID: activityContext.turnID
            )
            return true
        }
        guard let appState = routingContext.appState else { return true }
        AIActivityStore.shared.start(
            providerID: providerID,
            paneID: paneID,
            appState: appState,
            worktreeStore: routingContext.worktreeStore,
            sessionID: activityContext.sessionID,
            turnID: activityContext.turnID
        )
        return true
    }

    private static func handleProviderSession(providerID: String, paneID: UUID, body: String) -> Bool {
        guard let event = CodingAgentSessionEventBody.decode(body) else { return true }
        let now = Date()
        CodingAgentSessionMetadataStore.shared.update(CodingAgentSessionMetadata(
            providerID: providerID,
            paneID: paneID,
            sessionID: event.sessionID,
            transcriptPath: event.transcriptPath,
            title: event.title,
            cwd: event.cwd ?? event.worktreePath,
            source: event.source,
            updatedAt: now
        ))
        if AgentRunStore.shared.run(providerID: providerID, paneID: paneID) == nil,
           let projectID = event.projectID,
           let worktreeID = event.worktreeID
        {
            AgentRunStore.shared.start(
                providerID: providerID,
                paneID: paneID,
                projectID: projectID,
                worktreeID: worktreeID,
                worktreePath: event.worktreePath,
                title: event.title
            )
            CodingAgentSessionMetadataStore.shared.update(CodingAgentSessionMetadata(
                providerID: providerID,
                paneID: paneID,
                sessionID: event.sessionID,
                transcriptPath: event.transcriptPath,
                title: event.title,
                cwd: event.cwd ?? event.worktreePath,
                source: event.source,
                updatedAt: now
            ))
        }
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

    private static func activityContext(from body: String) -> ActivityContext {
        guard let data = body.data(using: .utf8),
              let event = try? JSONDecoder().decode(ActivityEventBody.self, from: data)
        else {
            return ActivityContext(explicitContext: explicitContext(from: body), sessionID: nil, turnID: nil)
        }

        let explicit: ExplicitContext? = if let projectID = event.projectID, let worktreeID = event.worktreeID {
            ExplicitContext(projectID: projectID, worktreeID: worktreeID, worktreePath: event.worktreePath)
        } else {
            nil
        }
        return ActivityContext(explicitContext: explicit, sessionID: event.sessionID, turnID: event.turnID)
    }
}
