import Foundation

@MainActor
final class KajiAgentActivityBridge {
    static let shared = KajiAgentActivityBridge()

    private init() {}

    func start(
        scope: KajiAgentScope?,
        appState: AppState?,
        worktreeStore: WorktreeStore?,
        sessionID: String?
    ) {
        guard let scope else { return }
        AIActivityStore.shared.start(
            providerID: AgentProviderCatalog.kajiAgentID,
            paneID: scope.agentID,
            projectID: scope.projectID,
            worktreeID: scope.worktreeID,
            worktreePath: scope.projectPath,
            sessionID: sessionID
        )
        recordSession(scope: scope, sessionID: sessionID, transcriptPath: nil)
    }

    func observe(scope: KajiAgentScope?, event: KajiAgentSessionEvent) {
        guard let scope else { return }
        AIActivityStore.shared.observe(providerID: AgentProviderCatalog.kajiAgentID, paneID: scope.agentID)
        if let prompt = KajiAgentRunSummary.promptText(from: event), !prompt.isEmpty {
            AIActivityStore.shared.appendTranscript(
                providerID: AgentProviderCatalog.kajiAgentID,
                paneID: scope.agentID,
                kind: "user",
                text: prompt
            )
        }
        if let tool = KajiAgentRunSummary.toolText(from: event), !tool.isEmpty {
            AIActivityStore.shared.appendTranscript(
                providerID: AgentProviderCatalog.kajiAgentID,
                paneID: scope.agentID,
                kind: "tool",
                text: tool
            )
        }
        if let assistant = KajiAgentRunSummary.assistantText(from: event), !assistant.isEmpty {
            AIActivityStore.shared.appendTranscript(
                providerID: AgentProviderCatalog.kajiAgentID,
                paneID: scope.agentID,
                kind: "assistant",
                text: assistant
            )
        }
    }

    func complete(
        scope: KajiAgentScope?,
        appState: AppState?,
        worktreeStore: WorktreeStore?,
        body: String,
        sessionID: String?
    ) {
        guard let scope else { return }
        recordSession(scope: scope, sessionID: sessionID, transcriptPath: nil)
        guard let appState else {
            completeDetached(scope: scope, body: body)
            return
        }
        guard let context = KajiAgentActivityContextResolver.context(scope: scope, appState: appState, worktreeStore: worktreeStore) else {
            completeDetached(scope: scope, body: body)
            return
        }
        NotificationStore.shared.addWithContext(
            context: context,
            paneID: scope.agentID,
            source: .aiProvider(AgentProviderCatalog.kajiAgentID),
            title: "Kaji Runtime",
            body: body,
            appState: appState
        )
    }

    func abort(scope: KajiAgentScope?, message: String) {
        guard let scope else { return }
        if AIActivityStore.shared.stop(paneID: scope.agentID) != nil {
            AgentRunStore.shared.complete(
                providerID: AgentProviderCatalog.kajiAgentID,
                paneID: scope.agentID,
                message: message
            )
        }
    }

    func fail(
        scope: KajiAgentScope?,
        appState: AppState?,
        worktreeStore: WorktreeStore?,
        message: String
    ) {
        guard let scope else { return }
        AIActivityStore.shared.markStale(paneID: scope.agentID, message: message)
        AgentRunStore.shared.fail(providerID: AgentProviderCatalog.kajiAgentID, paneID: scope.agentID, message: message)
        guard let appState else {
            NotificationStore.shared.addDetached(
                source: .aiProvider(AgentProviderCatalog.kajiAgentID),
                title: "Kaji Runtime failed",
                body: message
            )
            return
        }
        guard let context = KajiAgentActivityContextResolver.context(scope: scope, appState: appState, worktreeStore: worktreeStore) else {
            NotificationStore.shared.addDetached(
                source: .aiProvider(AgentProviderCatalog.kajiAgentID),
                title: "Kaji Runtime failed",
                body: message
            )
            return
        }
        NotificationStore.shared.addWithContext(
            context: context,
            paneID: scope.agentID,
            source: .aiProvider(AgentProviderCatalog.kajiAgentID),
            title: "Kaji Runtime failed",
            body: message,
            appState: appState
        )
    }

    func needsAttention(
        scope: KajiAgentScope?,
        appState: AppState?,
        worktreeStore: WorktreeStore?,
        kind: String,
        detail: String
    ) {
        guard let scope else { return }
        let title = attentionTitle(kind: kind)
        let body = KajiAgentRunSummary.clipped(detail.isEmpty ? title : detail, limit: 360)
        AIActivityStore.shared.recordAttention(
            providerID: AgentProviderCatalog.kajiAgentID,
            paneID: scope.agentID,
            kind: kind,
            text: body
        )
        guard let appState,
              let context = KajiAgentActivityContextResolver.context(scope: scope, appState: appState, worktreeStore: worktreeStore)
        else { return }
        NotificationStore.shared.addWithContext(
            context: context,
            paneID: scope.agentID,
            source: .aiProvider(AgentProviderCatalog.kajiAgentID),
            title: title,
            body: body,
            appState: appState
        )
    }

    func recordSession(scope: KajiAgentScope?, sessionID: String?, transcriptPath: String?) {
        guard let scope,
              let sessionID = sessionID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sessionID.isEmpty
        else { return }
        let metadata = CodingAgentSessionMetadata(
            providerID: AgentProviderCatalog.kajiAgentID,
            paneID: scope.agentID,
            sessionID: sessionID,
            transcriptPath: transcriptPath,
            title: "Kaji Runtime",
            cwd: scope.projectPath,
            source: "kaji-agent",
            updatedAt: Date()
        )
        CodingAgentSessionMetadataStore.shared.update(metadata)
        AgentRunStore.shared.setSessionMetadata(metadata)
    }

    private func attentionTitle(kind: String) -> String {
        kind == "approval" ? "Kaji Runtime needs approval" : "Kaji Runtime needs input"
    }

    private func completeDetached(scope: KajiAgentScope, body: String) {
        AIActivityStore.shared.stop(paneID: scope.agentID)
        AgentRunStore.shared.complete(providerID: AgentProviderCatalog.kajiAgentID, paneID: scope.agentID, message: body)
        NotificationStore.shared.addDetached(
            source: .aiProvider(AgentProviderCatalog.kajiAgentID),
            title: "Kaji Runtime",
            body: body
        )
    }
}
