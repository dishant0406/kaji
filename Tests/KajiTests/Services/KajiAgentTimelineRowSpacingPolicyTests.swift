import Foundation
import Testing

@testable import Kaji

struct KajiAgentTimelineRowSpacingPolicyTests {
    @Test
    func startsTurnsWithLargerSpacingThanNestedRows() {
        let turnID = UUID()
        let start = KajiAgentTimelineRow(
            id: .init(rawValue: "start"),
            turnID: turnID,
            startsTurn: true,
            isLatestTurn: false,
            kind: .message(KajiAgentMessage(kind: .assistant, title: "Kaji", detail: "Hi"))
        )
        let child = KajiAgentTimelineRow(
            id: .init(rawValue: "child"),
            turnID: turnID,
            startsTurn: false,
            isLatestTurn: false,
            kind: .tool(KajiAgentMessage(kind: .tool, title: "read", detail: ""), expanded: false),
            depth: 1,
            parentID: start.id
        )

        #expect(KajiAgentTimelineRowSpacingPolicy.topSpacing(for: start) > KajiAgentTimelineRowSpacingPolicy.topSpacing(for: child))
        #expect(KajiAgentTimelineRowSpacingPolicy.bottomSpacing(for: child) == KajiAgentTranscriptMetrics.nestedRowSpacing)
    }
}
