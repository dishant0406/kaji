import Foundation
import os

private let providerEventLogger = Logger(subsystem: "app.kaji", category: "ProviderEventDispatcher")

@MainActor
enum ProviderEventDispatcher {
    static func dispatch(_ event: ProviderEvent) {
        if AIActivitySocketRouter.handle(
            .init(type: event.type, title: event.title, body: event.body, paneIDString: event.paneIDString),
            appState: NotificationStore.shared.appState,
            worktreeStore: NotificationStore.shared.worktreeStore
        ) {
            return
        }

        let policy = AIProviderRegistry.shared.notificationPolicy(for: event.type)
        guard !suppressesRoutineCompletionEvent(event, policy: policy) else { return }

        let source = AIProviderRegistry.shared.notificationSource(for: event.type)
        guard let appState = NotificationStore.shared.appState else {
            NotificationStore.shared.addDetached(source: source, title: event.title, body: event.body)
            providerEventLogger.warning("Persisted detached notification: appState not ready")
            return
        }

        if let paneIDString = event.paneIDString, let paneID = UUID(uuidString: paneIDString) {
            completeProviderRunIfNeeded(source: source, paneID: paneID, title: event.title, body: event.body, appState: appState)
            guard !suppressesRoutineCompletionNotification(source: source, title: event.title, body: event.body) else { return }
            NotificationStore.shared.add(
                paneID: paneID,
                source: source,
                title: event.title,
                body: event.body,
                appState: appState
            )
            return
        }

        guard !suppressesRoutineCompletionNotification(source: source, title: event.title, body: event.body) else { return }

        guard let projectID = appState.activeProjectID,
              let key = appState.activeWorktreeKey(for: projectID),
              let context = NotificationFallbackContextResolver.resolve(
                  key: key,
                  appState: appState,
                  worktreeStore: NotificationStore.shared.worktreeStore
              )
        else {
            NotificationStore.shared.addDetached(source: source, title: event.title, body: event.body)
            providerEventLogger.warning("Persisted detached notification: no active pane context for provider event fallback")
            return
        }

        NotificationStore.shared.addWithContext(
            context: context,
            source: source,
            title: event.title,
            body: event.body,
            appState: appState
        )
    }

    private static func suppressesRoutineCompletionNotification(source: KajiNotification.Source, title: String, body: String) -> Bool {
        let policy = AIProviderRegistry.shared.notificationPolicy(for: source)
        guard policy.suppressRoutineProviderEvents else { return false }
        let text = "\(title) \(body)".lowercased()
        return !text.contains("needs permission") &&
            !text.contains("needs attention") &&
            !text.contains("question") &&
            !text.contains("error")
    }

    private static func suppressesRoutineCompletionEvent(_ event: ProviderEvent, policy: CodingAgentNotificationPolicy) -> Bool {
        guard policy.suppressRoutineProviderEvents else { return false }
        let text = "\(event.title) \(event.body)".lowercased()
        return !text.contains("needs permission") &&
            !text.contains("needs attention") &&
            !text.contains("question") &&
            !text.contains("error")
    }

    private static func completeProviderRunIfNeeded(
        source: KajiNotification.Source,
        paneID: UUID,
        title: String,
        body: String,
        appState: AppState
    ) {
        guard case let .aiProvider(providerID) = source else { return }
        let text = "\(title) \(body)".lowercased()
        guard !text.contains("needs permission"),
              !text.contains("needs attention"),
              !text.contains("question"),
              !text.contains("error")
        else { return }
        let activity = AIActivityStore.shared.stop(paneID: paneID)
        createCompletedRunIfMissing(providerID: providerID, paneID: paneID, appState: appState)
        AgentRunStore.shared.complete(
            providerID: providerID,
            paneID: paneID,
            message: body.isEmpty ? "Session completed" : body
        )
        if activity == nil {
            AIActivityStore.shared.captureChangedFiles(providerID: providerID, paneID: paneID)
        }
    }

    private static func createCompletedRunIfMissing(providerID: String, paneID: UUID, appState: AppState) {
        guard AgentRunStore.shared.run(providerID: providerID, paneID: paneID) == nil else { return }
        guard let worktreeStore = NotificationStore.shared.worktreeStore else { return }
        guard let context = NotificationNavigator.resolveContext(
            for: paneID,
            appState: appState,
            worktreeStore: worktreeStore
        )
        else { return }
        AgentRunStore.shared.start(
            providerID: providerID,
            paneID: paneID,
            projectID: context.projectID,
            worktreeID: context.worktreeID,
            worktreePath: context.worktreePath
        )
    }
}
