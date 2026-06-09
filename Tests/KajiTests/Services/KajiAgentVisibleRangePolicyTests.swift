import Testing

@testable import Kaji

struct KajiAgentVisibleRangePolicyTests {
    @Test
    func returnsVisibleRowsWithOverscan() {
        let layout = KajiAgentVisibleRangePolicy.layout(
            heights: Array(repeating: 20, count: 20),
            scrollOffset: 100,
            viewportHeight: 60,
            overscanScreens: 1
        )

        #expect(layout.range == 1 ..< 12)
        #expect(layout.topSpacerHeight == 20)
        #expect(layout.bottomSpacerHeight == 160)
        #expect(layout.totalHeight == 400)
    }

    @Test
    func handlesEmptyRows() {
        let layout = KajiAgentVisibleRangePolicy.layout(heights: [], scrollOffset: 0, viewportHeight: 100)

        #expect(layout.range == 0 ..< 0)
        #expect(layout.totalHeight == 0)
    }

    @Test
    func includesHugeIntersectingRow() {
        let layout = KajiAgentVisibleRangePolicy.layout(
            heights: [40, 1_000, 40],
            scrollOffset: 300,
            viewportHeight: 100,
            overscanScreens: 0
        )

        #expect(layout.range == 1 ..< 2)
        #expect(layout.topSpacerHeight == 40)
    }
}
