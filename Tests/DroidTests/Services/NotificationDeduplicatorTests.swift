import Foundation
import Testing

@testable import Droid

@MainActor
struct NotificationDeduplicatorTests {
    @Test
    func matchesSameSourceTitleBodyWithinFiveSeconds() {
        let first = DroidNotification(
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
        let duplicate = DroidNotification(
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

        #expect(NotificationDeduplicator.isDuplicate(duplicate, in: [first]))
    }

    @Test
    func ignoresDifferentBodies() {
        let first = DroidNotification(
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
        let second = DroidNotification(
            paneID: UUID(),
            projectID: UUID(),
            worktreeID: UUID(),
            areaID: UUID(),
            tabID: UUID(),
            worktreePath: "",
            source: .aiProvider("codex"),
            title: "Codex",
            body: "Different"
        )

        #expect(!NotificationDeduplicator.isDuplicate(second, in: [first]))
    }
}
