import Foundation
import Testing

@testable import Droid

@MainActor
struct CodingAgentNotificationCoalescerTests {
    @Test
    func replacesGenericCompletionWithRicherMessage() {
        var existing = [
            DroidNotification(
                paneID: UUID(),
                projectID: UUID(),
                worktreeID: UUID(),
                areaID: UUID(),
                tabID: UUID(),
                worktreePath: "",
                source: .aiProvider("codex"),
                title: "Codex",
                body: "Turn completed (codex-tui)"
            ),
        ]
        let richer = DroidNotification(
            paneID: UUID(),
            projectID: UUID(),
            worktreeID: UUID(),
            areaID: UUID(),
            tabID: UUID(),
            worktreePath: "",
            source: .aiProvider("codex"),
            title: "Codex",
            body: "Hello."
        )

        #expect(CodingAgentNotificationCoalescer.merge(richer, into: &existing) == .replaced)
        #expect(existing.first?.body == "Hello.")
    }

    @Test
    func skipsGenericCompletionWhenRicherMessageAlreadyExists() {
        var existing = [
            DroidNotification(
                paneID: UUID(),
                projectID: UUID(),
                worktreeID: UUID(),
                areaID: UUID(),
                tabID: UUID(),
                worktreePath: "",
                source: .aiProvider("codex"),
                title: "Codex",
                body: "Hello."
            ),
        ]
        let generic = DroidNotification(
            paneID: UUID(),
            projectID: UUID(),
            worktreeID: UUID(),
            areaID: UUID(),
            tabID: UUID(),
            worktreePath: "",
            source: .aiProvider("codex"),
            title: "Codex",
            body: "Turn completed (codex-tui)"
        )

        #expect(CodingAgentNotificationCoalescer.merge(generic, into: &existing) == .ignored)
        #expect(existing.first?.body == "Hello.")
    }
}
