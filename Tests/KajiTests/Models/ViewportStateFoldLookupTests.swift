import Testing

@testable import Kaji

@Suite("ViewportState folded lookup")
@MainActor
struct ViewportStateFoldLookupTests {
    @Test("scrollY maps folded lines to the nearest visible line")
    func scrollYForFoldedLineUsesNearestVisibleLine() {
        let store = TextBackingStore()
        store.loadFromText((0 ..< 12).map { "line \($0)" }.joined(separator: "\n"))
        let viewport = ViewportState(backingStore: store)

        viewport.rebuildVisualLines(collapsedRegions: [EditorFoldRegion(startLine: 2, endLine: 7)])

        #expect(viewport.viewportLine(forBackingStoreLine: 8) == nil)
        viewport.applyViewport(0 ..< viewport.visualLineCount)
        #expect(viewport.viewportLine(forBackingStoreLine: 8) == 3)
        #expect(viewport.viewportLine(forBackingStoreLine: 4) == nil)
        #expect(viewport.scrollY(forLine: 4) == viewport.scrollY(forLine: 2))
    }
}
