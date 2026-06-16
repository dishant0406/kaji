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
    func toolGroupBecomesActivitySummary() {
        let group = KajiAgentToolGroup(tools: [KajiAgentMessage(kind: .tool, title: "bash", detail: "1 line")])
        let turn = KajiAgentTurn(blocks: [.toolGroup(group)])

        let rows = KajiAgentTimelineFlattener.rows(
            turns: [turn],
            widgetLines: [],
            queuedMessageCount: 0
        )

        #expect(rows.map(\.kindName) == ["activity", "bottom"])
        #expect(rows[0].depth == 0)
        #expect(rows[0].parentID == nil)
    }

    @Test
    func expandedToolGroupKeepsActivityInline() {
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

        #expect(rows.map(\.kindName) == ["activity", "bottom"])
        #expect(rows[0].depth == 0)
        guard case let .activity(activity, expanded) = rows[0].kind else {
            Issue.record("Expected activity row")
            return
        }
        #expect(activity.actions.count == 2)
        #expect(expanded)
    }

    @Test
    func thinkingRowsBecomePlanSummaries() throws {
        let thinking = KajiAgentMessage(kind: .thinking, title: "Thinking", detail: "Analyzing")
        let turn = KajiAgentTurn(blocks: [.message(thinking)])

        let rows = KajiAgentTimelineFlattener.rows(
            turns: [turn],
            widgetLines: [],
            queuedMessageCount: 0,
            expansion: KajiAgentTimelineExpansionState(thinking: [thinking.id])
        )

        guard case let .plan(plan, expanded) = rows[0].kind else {
            Issue.record("Expected plan row")
            return
        }
        #expect(plan.id == thinking.id)
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
        case .plan: "plan"
        case .activity: "activity"
        case .thinking: "thinking"
        case .toolGroupHeader: "toolGroup"
        case .tool: "tool"
        case .latestTurnSpacer: "spacer"
        case .bottom: "bottom"
        }
    }
}
