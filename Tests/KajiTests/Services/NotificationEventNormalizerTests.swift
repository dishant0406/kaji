import Foundation
import Testing

@testable import Kaji

@MainActor
struct NotificationEventNormalizerTests {
    @Test
    func codexCompletionBecomesCompletedCodexEvent() {
        let notification = KajiNotification(
            paneID: UUID(),
            projectID: UUID(),
            worktreeID: UUID(),
            areaID: UUID(),
            tabID: UUID(),
            worktreePath: "/Users/dishants/projects/muxy",
            source: .aiProvider("codex"),
            title: "Turn completed",
            body: "Ready"
        )

        let event = NotificationEventNormalizer.normalize(
            notification: notification,
            appState: nil,
            worktreeStore: nil
        )

        #expect(event.source == .codex)
        #expect(event.kind == .completed)
        #expect(event.title == "Turn completed · muxy")
        #expect(event.project == "muxy")
        #expect(event.worktree == "muxy")
    }


    @Test
    func kajiAgentCompletionBecomesCompletedKajiAgentEvent() {
        let notification = KajiNotification(
            paneID: UUID(),
            projectID: UUID(),
            worktreeID: UUID(),
            areaID: UUID(),
            tabID: UUID(),
            worktreePath: "/Users/dishants/projects/muxy",
            source: .aiProvider(AgentProviderCatalog.kajiAgentID),
            title: "Kaji Runtime",
            body: "Finished"
        )

        let event = NotificationEventNormalizer.normalize(
            notification: notification,
            appState: nil,
            worktreeStore: nil
        )

        #expect(event.source.rawValue == "Kaji Runtime")
        #expect(event.kind == .completed)
        #expect(event.title == "Kaji Runtime · muxy")
    }

    @Test
    func errorTextBecomesErrorEvent() {
        let notification = KajiNotification(
            paneID: UUID(),
            projectID: UUID(),
            worktreeID: UUID(),
            areaID: UUID(),
            tabID: UUID(),
            worktreePath: "/tmp/demo",
            source: .socket,
            title: "Task failed",
            body: "Request error"
        )

        let event = NotificationEventNormalizer.normalize(
            notification: notification,
            appState: nil,
            worktreeStore: nil
        )

        #expect(event.source == .custom)
        #expect(event.kind == .error)
    }
}
