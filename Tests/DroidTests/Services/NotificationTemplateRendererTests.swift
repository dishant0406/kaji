import Foundation
import Testing

@testable import Droid

struct NotificationTemplateRendererTests {
    @Test
    func replacesKnownTokens() {
        let rendered = NotificationTemplateRenderer.render(
            "{{title}}|{{body}}|{{source}}|{{event_kind}}|{{project}}|{{worktree}}",
            event: .sample
        )

        #expect(rendered == "Turn completed|The run completed successfully.|Codex|Completed|Droid|muxy")
    }
}
