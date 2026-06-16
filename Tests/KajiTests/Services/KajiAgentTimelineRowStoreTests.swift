import Testing

@testable import Kaji

@MainActor
struct KajiAgentTimelineRowStoreTests {
    @Test
    func expandsAndCollapsesActivityInline() throws {
        let group = KajiAgentToolGroup(tools: [
            KajiAgentMessage(kind: .tool, title: "read", detail: "1 line"),
            KajiAgentMessage(kind: .tool, title: "bash", detail: "1 line"),
        ])
        let store = KajiAgentTimelineRowStore()
        store.rebuild(turns: [KajiAgentTurn(blocks: [.toolGroup(group)])], widgetLines: [], queuedMessageCount: 0)

        #expect(store.rows.map(\.kindName) == ["activity", "bottom"])
        store.toggleToolGroup(group.id)
        #expect(store.rows.map(\.kindName) == ["activity", "bottom"])
        #expect(store.rows[0].isActivityExpanded)
        store.toggleToolGroup(group.id)
        #expect(store.rows.map(\.kindName) == ["activity", "bottom"])
        #expect(store.rows[0].isActivityExpanded == false)
    }

    @Test
    func preservesExpandedGroupsAcrossRebuild() {
        let group = KajiAgentToolGroup(tools: [KajiAgentMessage(kind: .tool, title: "read", detail: "1 line")])
        let store = KajiAgentTimelineRowStore()
        let turns = [KajiAgentTurn(blocks: [.toolGroup(group)])]
        store.rebuild(turns: turns, widgetLines: [], queuedMessageCount: 0)
        store.toggleToolGroup(group.id)

        store.rebuild(turns: turns, widgetLines: [], queuedMessageCount: 0)

        #expect(store.rows.map(\.kindName) == ["activity", "bottom"])
        #expect(store.rows[0].isActivityExpanded)
    }

    @Test
    func togglesThinkingRowWithoutRebuildingTimeline() throws {
        let thinking = KajiAgentMessage(kind: .thinking, title: "Thinking", detail: "Analyzing")
        let store = KajiAgentTimelineRowStore()
        let turns = [KajiAgentTurn(blocks: [.message(thinking)])]
        store.rebuild(turns: turns, widgetLines: [], queuedMessageCount: 0)

        #expect(store.rows.map(\.kindName) == ["plan", "bottom"])
        #expect(store.rows[0].isThinkingExpanded == false)

        store.toggleThinking(thinking.id)

        #expect(store.rows.map(\.kindName) == ["plan", "bottom"])
        #expect(store.rows[0].isThinkingExpanded)

        store.rebuild(turns: turns, widgetLines: [], queuedMessageCount: 0)

        #expect(store.rows[0].isThinkingExpanded)
    }
}

private extension KajiAgentTimelineRow {
    var isThinkingExpanded: Bool {
        if case let .plan(_, expanded) = kind { return expanded }
        if case let .thinking(_, expanded) = kind { return expanded }
        return false
    }

    var isActivityExpanded: Bool {
        if case let .activity(_, expanded) = kind { return expanded }
        return false
    }

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
