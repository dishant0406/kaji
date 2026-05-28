import Testing
@testable import Kaji

@Suite("ViewportState scroll clamping")
@MainActor
struct ViewportStateScrollClampTests {
    private func makeViewport(lineCount: Int) -> ViewportState {
        let store = TextBackingStore()
        store.loadFromText((0 ..< lineCount).map { "line \($0)" }.joined(separator: "\n"))
        return ViewportState(backingStore: store)
    }

    @Test("maximum content scroll excludes decorative padding")
    func maximumContentScrollExcludesDecorativePadding() {
        let viewport = makeViewport(lineCount: 100)
        viewport.updateDocumentPadding(topInset: 4, bottomInset: 96)

        #expect(viewport.totalDocumentHeight == 1700)
        #expect(viewport.scrollableDocumentHeight == 1600)
        #expect(viewport.maximumContentScrollY(visibleHeight: 160) == 1440)
    }

    @Test("scrollable document height excludes decorative padding")
    func scrollableDocumentHeightExcludesDecorativePadding() {
        let viewport = makeViewport(lineCount: 100)
        viewport.updateDocumentPadding(topInset: 4, bottomInset: 240)

        #expect(viewport.totalDocumentHeight == 1844)
        #expect(viewport.scrollableDocumentHeight == 1600)
    }

    @Test("clamped scroll y removes stale bottom overscroll")
    func clampedScrollYRemovesBottomOverscroll() {
        let viewport = makeViewport(lineCount: 100)
        viewport.updateDocumentPadding(topInset: 4, bottomInset: 96)

        #expect(viewport.clampedScrollY(scrollY: 1540, visibleHeight: 160) == 1440)
        #expect(viewport.clampedScrollY(scrollY: -20, visibleHeight: 160) == 0)
    }

    @Test("small upward scroll near bottom remains above bottom")
    func smallUpwardScrollNearBottomRemainsAboveBottom() {
        let viewport = makeViewport(lineCount: 100)
        viewport.updateDocumentPadding(topInset: 4, bottomInset: 240)

        #expect(viewport.clampedScrollY(scrollY: 1436, visibleHeight: 160) == 1436)
        #expect(viewport.visibleLineRange(scrollY: 1436, visibleHeight: 160) == 89 ..< 100)
    }
}
