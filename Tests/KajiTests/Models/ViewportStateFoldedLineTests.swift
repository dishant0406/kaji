import Testing
@testable import Kaji

@Suite("ViewportState folded lines")
@MainActor
struct ViewportStateFoldedLineTests {
    @Test("folded viewport maps only visible lines")
    func foldedViewportMapsVisibleLines() {
        let store = TextBackingStore()
        let text = (0 ..< 8).map { "line \($0)" }.joined(separator: "\n")
        store.loadFromText(text)
        let vp = ViewportState(backingStore: store)

        vp.rebuildVisualLines(collapsedRegions: [EditorFoldRegion(startLine: 1, endLine: 4)])
        vp.applyViewport(0 ..< 4)

        #expect(vp.visualLineCount == 5)
        #expect(vp.viewportText() == "line 0\nline 1\nline 5\nline 6")
        #expect(vp.viewportLine(forBackingStoreLine: 3) == nil)
        #expect(vp.viewportLine(forBackingStoreLine: 5) == 2)
        #expect(vp.isLineFolded(3))
    }
}
