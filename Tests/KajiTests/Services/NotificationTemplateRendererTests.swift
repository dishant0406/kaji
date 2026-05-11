import Foundation
import Testing

@testable import Kaji

struct NotificationTemplateRendererTests {
    @Test
    func replacesKnownTokens() {
        let rendered = NotificationTemplateRenderer.render(
            "{{title}}|{{body}}|{{source}}|{{event_kind}}|{{project}}|{{worktree}}",
            event: .sample
        )

        #expect(rendered == "Turn completed|The run completed successfully.|Codex|Completed|Kaji|muxy")
    }
}
