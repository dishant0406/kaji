import Foundation
import Testing

@testable import Droid

struct NotificationRoutingRuleTests {
    @Test
    func matchesConfiguredSourceAndKind() {
        let route = NotificationRoutingRule(
            name: "Codex completions",
            source: .codex,
            eventKind: .completed,
            sound: .glass,
            destinationIDs: [UUID()]
        )

        #expect(route.matches(.sample))
        #expect(route.sound == .glass)
    }

    @Test
    func anyFiltersMatchCustomEvents() {
        let route = NotificationRoutingRule(
            name: "Everything",
            source: .any,
            eventKind: .any,
            destinationIDs: [UUID()]
        )
        let event = NotificationOutboundEvent(
            source: .custom,
            kind: .info,
            title: "Done",
            body: "Webhook finished.",
            project: "Droid",
            worktree: "muxy",
            timestamp: .init(timeIntervalSince1970: 0)
        )

        #expect(route.matches(event))
    }
}
