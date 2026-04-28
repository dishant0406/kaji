import Foundation
import Testing

@testable import Droid

@MainActor
struct CodexNotificationCoalescerTests {
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

        #expect(CodexNotificationCoalescer.merge(richer, into: &existing))
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

        #expect(CodexNotificationCoalescer.merge(generic, into: &existing))
        #expect(existing.first?.body == "Hello.")
    }
}
