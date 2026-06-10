import Foundation
import Testing

@testable import Kaji

struct KajiAgentTimelineHeightEstimatorTests {
    @Test
    func collapsedThinkingStaysCompact() {
        let message = KajiAgentMessage(
            kind: .thinking,
            title: "Thinking",
            detail: String(repeating: "reasoning ", count: 120)
        )
        let row = KajiAgentTimelineRow(
            id: .init(rawValue: "thinking"),
            turnID: nil,
            startsTurn: false,
            isLatestTurn: false,
            kind: .thinking(message, expanded: false)
        )

        #expect(KajiAgentTimelineHeightEstimator.estimate(row) <= 40)
    }

    @Test
    func expandedThinkingIsBoundedToContentPreview() {
        let message = KajiAgentMessage(
            kind: .thinking,
            title: "Thinking",
            detail: String(repeating: "reasoning ", count: 400)
        )
        let row = KajiAgentTimelineRow(
            id: .init(rawValue: "thinking"),
            turnID: nil,
            startsTurn: false,
            isLatestTurn: false,
            kind: .thinking(message, expanded: true)
        )

        #expect(KajiAgentTimelineHeightEstimator.estimate(row) <= 270)
    }

    @Test
    func expandedToolAddsOnlyBoundedOutputHeight() {
        var message = KajiAgentMessage(kind: .tool, title: "bash", detail: "")
        message.fullOutput = String(repeating: "output\n", count: 300)
        let collapsed = row(for: message, expanded: false)
        let expanded = row(for: message, expanded: true)

        #expect(KajiAgentTimelineHeightEstimator.estimate(collapsed) < KajiAgentTimelineHeightEstimator.estimate(expanded))
        #expect(KajiAgentTimelineHeightEstimator.estimate(expanded) <= 490)
    }

    private func row(for message: KajiAgentMessage, expanded: Bool) -> KajiAgentTimelineRow {
        KajiAgentTimelineRow(
            id: .init(rawValue: "tool"),
            turnID: nil,
            startsTurn: false,
            isLatestTurn: false,
            kind: .tool(message, expanded: expanded)
        )
    }
}
