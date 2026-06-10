import Testing

@testable import Kaji

struct KajiAgentTimelineFlattenerTests {
    @Test
    func flattensWidgetQueuedMessagesAndTurnsInOrder() {
        let turn = KajiAgentTurn(user: KajiAgentMessage(kind: .user, title: "You", detail: "Build"), blocks: [
            .message(KajiAgentMessage(kind: .assistant, title: "Kaji", detail: "Done")),
        ])

        let rows = KajiAgentTimelineFlattener.rows(
            turns: [turn],
            widgetLines: ["status"],
            queuedMessageCount: 2
        )

        #expect(rows.map(\.kindName) == ["widget", "queued", "user", "message", "bottom"])
        #expect(rows[2].startsTurn)
        #expect(rows[3].startsTurn == false)
        #expect(rows.allSatisfy { $0.depth == 0 })
    }

    @Test
    func collapsedToolGroupOnlyIncludesHeader() {
        let group = KajiAgentToolGroup(tools: [KajiAgentMessage(kind: .tool, title: "bash", detail: "1 line")])
        let turn = KajiAgentTurn(blocks: [.toolGroup(group)])

        let rows = KajiAgentTimelineFlattener.rows(
            turns: [turn],
            widgetLines: [],
            queuedMessageCount: 0
        )

        #expect(rows.map(\.kindName) == ["toolGroup", "bottom"])
        #expect(rows[0].depth == 0)
        #expect(rows[0].parentID == nil)
    }

    @Test
    func expandedToolGroupIncludesToolRows() {
        let group = KajiAgentToolGroup(tools: [
            KajiAgentMessage(kind: .tool, title: "read", detail: "1 line"),
            KajiAgentMessage(kind: .tool, title: "bash", detail: "1 line"),
        ])
        let turn = KajiAgentTurn(blocks: [.toolGroup(group)])

        let rows = KajiAgentTimelineFlattener.rows(
            turns: [turn],
            widgetLines: [],
            queuedMessageCount: 0,
            expansion: KajiAgentTimelineExpansionState(toolGroups: [group.id])
        )

        #expect(rows.map(\.kindName) == ["toolGroup", "tool", "tool", "bottom"])
        #expect(rows[0].depth == 0)
        #expect(rows[1].depth == 1)
        #expect(rows[2].depth == 1)
        #expect(rows[1].parentID == rows[0].id)
        #expect(rows[2].parentID == rows[0].id)
    }

    @Test
    func thinkingRowsCarryExpandedState() throws {
        let thinking = KajiAgentMessage(kind: .thinking, title: "Thinking", detail: "Analyzing")
        let turn = KajiAgentTurn(blocks: [.message(thinking)])

        let rows = KajiAgentTimelineFlattener.rows(
            turns: [turn],
            widgetLines: [],
            queuedMessageCount: 0,
            expansion: KajiAgentTimelineExpansionState(thinking: [thinking.id])
        )

        guard case let .thinking(message, expanded) = rows[0].kind else {
            Issue.record("Expected thinking row")
            return
        }
        #expect(message.id == thinking.id)
        #expect(expanded)
    }
}

private extension KajiAgentTimelineRow {
    var kindName: String {
        switch kind {
        case .widget: "widget"
        case .queuedMessages: "queued"
        case .user: "user"
        case .message: "message"
        case .thinking: "thinking"
        case .toolGroupHeader: "toolGroup"
        case .tool: "tool"
        case .latestTurnSpacer: "spacer"
        case .bottom: "bottom"
        }
    }
}
