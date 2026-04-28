import Foundation
import Testing

@testable import Droid

struct NotificationRouteSoundResolverTests {
    @Test
    func usesRouteSoundWhenMatchingOverrideExists() {
        let sound = NotificationRouteSoundResolver.resolve(
            routes: [
                NotificationRoutingRule(
                    name: "Codex completions",
                    source: .codex,
                    eventKind: .completed,
                    sound: .glass,
                    destinationIDs: [UUID()]
                ),
            ],
            event: .sample,
            defaultSound: .funk
        )

        #expect(sound == .glass)
    }

    @Test
    func fallsBackToDefaultSoundWhenRuleHasNoOverride() {
        let sound = NotificationRouteSoundResolver.resolve(
            routes: [
                NotificationRoutingRule(
                    name: "Codex completions",
                    source: .codex,
                    eventKind: .completed,
                    destinationIDs: [UUID()]
                ),
            ],
            event: .sample,
            defaultSound: .funk
        )

        #expect(sound == .funk)
    }
}
