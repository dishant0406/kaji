import Testing

@testable import Kaji

@MainActor
struct KajiAgentTimelineHeightIndexTests {
    @Test
    func computesVisibleLayoutWithPrefixSums() {
        let index = KajiAgentTimelineHeightIndex()
        index.sync(rows: rows(count: 20))

        let layout = index.layout(scrollOffset: 100, viewportHeight: 60, overscanScreens: 1)

        #expect(layout.range == 1 ..< 12)
        #expect(layout.topSpacerHeight == 20)
        #expect(layout.bottomSpacerHeight == 160)
        #expect(layout.totalHeight == 400)
    }

    @Test
    func appliesMeasurementsAndReturnsCorrectionAboveViewport() {
        let store = KajiAgentTimelineRowStore()
        store.rebuild(turns: makeTurns(3), widgetLines: [], queuedMessageCount: 0)
        let index = KajiAgentTimelineHeightIndex()
        index.sync(rows: store.rows)

        let result = index.applyMeasurements(
            [KajiAgentTimelineRowHeightValue(id: store.rows[0].id, height: 80)],
            rowStore: store,
            scrollOffset: 100
        )

        #expect(result.changedCount == 1)
        #expect(result.correction > 0)
    }

    @Test
    func syncPrunesRemovedRows() {
        let store = KajiAgentTimelineRowStore()
        store.rebuild(turns: makeTurns(2), widgetLines: [], queuedMessageCount: 0)
        let index = KajiAgentTimelineHeightIndex()
        index.sync(rows: store.rows)
        _ = index.applyMeasurements(
            [KajiAgentTimelineRowHeightValue(id: store.rows[0].id, height: 80)],
            rowStore: store,
            scrollOffset: 0
        )

        store.rebuild(turns: makeTurns(1), widgetLines: [], queuedMessageCount: 0)
        index.sync(rows: store.rows)

        #expect(index.layout(scrollOffset: 0, viewportHeight: 100).totalHeight < 180)
    }

    @Test
    func syncDropsMeasuredHeightWhenExpansionStateChanges() {
        let thinking = KajiAgentMessage(
            kind: .thinking,
            title: "Thinking",
            detail: String(repeating: "reasoning ", count: 120)
        )
        let store = KajiAgentTimelineRowStore()
        store.rebuild(turns: [KajiAgentTurn(blocks: [.message(thinking)])], widgetLines: [], queuedMessageCount: 0)
        let index = KajiAgentTimelineHeightIndex()
        index.sync(rows: store.rows)
        _ = index.applyMeasurements(
            [KajiAgentTimelineRowHeightValue(id: store.rows[0].id, height: 300)],
            rowStore: store,
            scrollOffset: 0
        )

        store.toggleThinking(thinking.id)
        index.sync(rows: store.rows)

        #expect(index.layout(scrollOffset: 0, viewportHeight: 100).totalHeight < 300)
    }

    private func rows(count: Int) -> [KajiAgentTimelineRow] {
        (0 ..< count).map { item in
            KajiAgentTimelineRow(
                id: .init(rawValue: "row.\(item)"),
                turnID: nil,
                startsTurn: false,
                isLatestTurn: false,
                kind: .latestTurnSpacer(20)
            )
        }
    }

    private func makeTurns(_ count: Int) -> [KajiAgentTurn] {
        (0 ..< count).map { index in
            KajiAgentTurn(user: KajiAgentMessage(kind: .user, title: "You", detail: "Turn \(index)"))
        }
    }
}
