import Testing

@testable import Kaji

@MainActor
struct KajiAgentTimelineRowStoreTests {
    @Test
    func expandsAndCollapsesToolGroupIncrementally() throws {
        let group = KajiAgentToolGroup(tools: [
            KajiAgentMessage(kind: .tool, title: "read", detail: "1 line"),
            KajiAgentMessage(kind: .tool, title: "bash", detail: "1 line"),
        ])
        let store = KajiAgentTimelineRowStore()
        store.rebuild(turns: [KajiAgentTurn(blocks: [.toolGroup(group)])], widgetLines: [], queuedMessageCount: 0)

        #expect(store.rows.map(\.kindName) == ["toolGroup", "bottom"])
        store.toggleToolGroup(group.id)
        #expect(store.rows.map(\.kindName) == ["toolGroup", "tool", "tool", "bottom"])
        #expect(store.rows[1].parentID == store.rows[0].id)
        #expect(store.index(for: store.rows[2].id) == 2)
        store.toggleToolGroup(group.id)
        #expect(store.rows.map(\.kindName) == ["toolGroup", "bottom"])
    }

    @Test
    func preservesExpandedGroupsAcrossRebuild() {
        let group = KajiAgentToolGroup(tools: [KajiAgentMessage(kind: .tool, title: "read", detail: "1 line")])
        let store = KajiAgentTimelineRowStore()
        let turns = [KajiAgentTurn(blocks: [.toolGroup(group)])]
        store.rebuild(turns: turns, widgetLines: [], queuedMessageCount: 0)
        store.toggleToolGroup(group.id)

        store.rebuild(turns: turns, widgetLines: [], queuedMessageCount: 0)

        #expect(store.rows.map(\.kindName) == ["toolGroup", "tool", "bottom"])
    }
}

private extension KajiAgentTimelineRow {
    var kindName: String {
        switch kind {
        case .widget: "widget"
        case .queuedMessages: "queued"
        case .user: "user"
        case .message: "message"
        case .toolGroupHeader: "toolGroup"
        case .tool: "tool"
        case .latestTurnSpacer: "spacer"
        case .bottom: "bottom"
        }
    }
}
