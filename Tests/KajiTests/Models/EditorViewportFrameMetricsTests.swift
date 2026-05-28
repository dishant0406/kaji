import CoreGraphics
import Testing

@testable import Kaji

@Suite("EditorViewportFrameMetrics")
struct EditorViewportFrameMetricsTests {
    @Test("keeps viewport at least as wide as the scroll view")
    func minimumViewportWidth() {
        let metrics = EditorViewportFrameMetrics.make(
            usedTextSize: CGSize(width: 120, height: 80),
            minimumWidth: 500,
            estimatedHeight: 40,
            horizontalPadding: 16,
            verticalInset: 20
        )

        #expect(metrics.viewportWidth == 500)
        #expect(metrics.contentHeight == 100)
    }

    @Test("expands viewport to include laid out content and padding")
    func laidOutContentSize() {
        let metrics = EditorViewportFrameMetrics.make(
            usedTextSize: CGSize(width: 503.2, height: 240.4),
            minimumWidth: 300,
            estimatedHeight: 120,
            horizontalPadding: 16,
            verticalInset: 20
        )

        #expect(metrics.viewportWidth == 520)
        #expect(metrics.contentHeight == 261)
    }

    @Test("falls back to estimated height without layout information")
    func fallbackMetrics() {
        let metrics = EditorViewportFrameMetrics.make(
            usedTextSize: nil,
            minimumWidth: 400,
            estimatedHeight: 180,
            horizontalPadding: 16,
            verticalInset: 20
        )

        #expect(metrics.viewportWidth == 400)
        #expect(metrics.contentHeight == 180)
    }
}
