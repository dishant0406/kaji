import CoreGraphics
import Testing

@testable import Kaji

@Suite("EditorViewportLayoutPolicy")
struct EditorViewportLayoutPolicyTests {
    @Test("skips text layout measurement during scroll driven refresh")
    func scrollDrivenMeasurementPolicy() {
        #expect(!EditorViewportLayoutPolicy.shouldMeasureTextLayout(isScrollDrivenRefresh: true))
        #expect(EditorViewportLayoutPolicy.shouldMeasureTextLayout(isScrollDrivenRefresh: false))
    }

    @Test("preserves current text width when layout measurement is skipped")
    func minimumWidthPreservesCurrentWidth() {
        #expect(EditorViewportLayoutPolicy.minimumViewportWidth(
            scrollContentWidth: 500,
            currentTextWidth: 900,
            preservesCurrentWidth: true
        ) == 900)
        #expect(EditorViewportLayoutPolicy.minimumViewportWidth(
            scrollContentWidth: 500,
            currentTextWidth: 900,
            preservesCurrentWidth: false
        ) == 500)
    }
}
