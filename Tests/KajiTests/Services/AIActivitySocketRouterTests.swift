import Foundation
import Testing

@testable import Kaji

@MainActor
struct AIActivitySocketRouterTests {
    @Test
    func explicitContextStartsAndStopsActivity() {
        let store = AIActivityStore.shared
        store.reset()

        let paneID = UUID()
        let projectID = UUID()
        let worktreeID = UUID()
        let payloadBody = "\(projectID.uuidString),\(worktreeID.uuidString),/tmp/muxy"

        let handledStart = AIActivitySocketRouter.handle(
            .init(
                type: "opencode_activity",
                title: "start",
                body: payloadBody,
                paneIDString: paneID.uuidString
            ),
            appState: nil,
            worktreeStore: nil
        )

        #expect(handledStart)
        #expect(store.activitiesByPaneID[paneID]?.projectID == projectID)
        #expect(store.activitiesByPaneID[paneID]?.worktreeID == worktreeID)
        #expect(store.activitiesByPaneID[paneID]?.worktreePath == "/tmp/muxy")
        #expect(AgentRunStore.shared.runs.first?.paneID == paneID)
        #expect(AgentRunStore.shared.runs.first?.worktreePath == "/tmp/muxy")
        #expect(AgentRunStore.shared.runs.first?.status == .running)

        let handledStop = AIActivitySocketRouter.handle(
            .init(
                type: "opencode_activity",
                title: "stop",
                body: payloadBody,
                paneIDString: paneID.uuidString
            ),
            appState: nil,
            worktreeStore: nil
        )

        #expect(handledStop)
        #expect(store.activitiesByPaneID[paneID] == nil)
        #expect(AgentRunStore.shared.runs.first?.paneID == paneID)
        #expect(AgentRunStore.shared.runs.first?.status == .completed)
    }

    @Test
    func explicitContextStopsActivityWhenPaneLookupIsUnavailable() {
        let store = AIActivityStore.shared
        store.reset()

        let startedPaneID = UUID()
        let stoppedPaneID = UUID()
        let projectID = UUID()
        let worktreeID = UUID()
        let payloadBody = "\(projectID.uuidString),\(worktreeID.uuidString),/tmp/muxy"

        store.start(
            providerID: "claude",
            paneID: startedPaneID,
            projectID: projectID,
            worktreeID: worktreeID
        )

        let handledStop = AIActivitySocketRouter.handle(
            .init(
                type: "claude_activity",
                title: "stop",
                body: payloadBody,
                paneIDString: stoppedPaneID.uuidString
            ),
            appState: nil,
            worktreeStore: nil
        )

        #expect(handledStop)
        #expect(!store.hasActiveAgent(projectID: projectID))
        #expect(AgentRunStore.shared.runs.first?.paneID == startedPaneID)
        #expect(AgentRunStore.shared.runs.first?.status == .completed)
    }

    @Test
    func transcriptPayloadAppendsToActiveActivity() {
        let store = AIActivityStore.shared
        store.reset()

        let paneID = UUID()
        let projectID = UUID()
        let worktreeID = UUID()
        store.start(providerID: "codex", paneID: paneID, projectID: projectID, worktreeID: worktreeID)

        let handled = AIActivitySocketRouter.handle(
            .init(
                type: "codex_transcript",
                title: "tool",
                body: "Read Package.swift",
                paneIDString: paneID.uuidString
            ),
            appState: nil,
            worktreeStore: nil
        )

        #expect(handled)
        #expect(store.activitiesByPaneID[paneID]?.transcriptEntries.first?.kind == "tool")
        #expect(store.activitiesByPaneID[paneID]?.transcriptEntries.first?.text == "Read Package.swift")
        #expect(AgentRunStore.shared.runs.first?.events.last?.label == "tool")
        #expect(AgentRunStore.shared.runs.first?.events.last?.text == "Read Package.swift")
        store.reset()
    }

    @Test
    func attentionPayloadMarksRunNeedsAttention() {
        let store = AIActivityStore.shared
        store.reset()

        let paneID = UUID()
        store.start(providerID: "codex", paneID: paneID, projectID: UUID(), worktreeID: UUID())

        let handled = AIActivitySocketRouter.handle(
            .init(
                type: "codex_attention",
                title: "permission",
                body: "Bash: npm install",
                paneIDString: paneID.uuidString
            ),
            appState: nil,
            worktreeStore: nil
        )

        #expect(handled)
        #expect(store.activitiesByPaneID[paneID]?.transcriptEntries.first?.kind == "permission")
        #expect(AgentRunStore.shared.runs.first?.status == .needsAttention)
        #expect(AgentRunStore.shared.runs.first?.events.last?.kind == .attention)
        #expect(AgentRunStore.shared.runs.first?.events.last?.label == "permission")
        #expect(AgentRunStore.shared.runs.first?.events.last?.text == "Bash: npm install")
        store.reset()
    }
}
