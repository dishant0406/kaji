import Testing
@testable import Kaji

@Suite("ViewportState")
@MainActor
struct ViewportStateTests {
    private func makeViewport(lineCount: Int) -> ViewportState {
        let store = TextBackingStore()
        let text = (0 ..< lineCount).map { "line \($0)" }.joined(separator: "\n")
        store.loadFromText(text)
        return ViewportState(backingStore: store)
    }

    @Test("initial state has zero viewport and default line height")
    func initialState() {
        let vp = makeViewport(lineCount: 100)
        #expect(vp.viewportStartLine == 0)
        #expect(vp.viewportEndLine == 0)
        #expect(vp.estimatedLineHeight == 16)
        #expect(vp.viewportLineCount == 0)
    }

    @Test("totalDocumentHeight includes document padding")
    func totalDocumentHeight() {
        let vp = makeViewport(lineCount: 100)
        #expect(vp.totalDocumentHeight == 1608)
    }

    @Test("visibleLineRange at scroll 0")
    func visibleLineRangeTop() {
        let vp = makeViewport(lineCount: 100)
        let range = vp.visibleLineRange(scrollY: 0, visibleHeight: 160)
        #expect(range == 0 ..< 10)
    }

    @Test("visibleLineRange mid-scroll")
    func visibleLineRangeMid() {
        let vp = makeViewport(lineCount: 100)
        let range = vp.visibleLineRange(scrollY: 320, visibleHeight: 160)
        #expect(range.lowerBound == 20)
        #expect(range.upperBound == 30)
    }

    @Test("visibleLineRange clamps to lineCount")
    func visibleLineRangeClamp() {
        let vp = makeViewport(lineCount: 5)
        let range = vp.visibleLineRange(scrollY: 0, visibleHeight: 1600)
        #expect(range.upperBound == 5)
    }

    @Test("visibleLineRange clamps lower bound after stale overscroll")
    func visibleLineRangeClampsLowerBoundAfterOverscroll() {
        let vp = makeViewport(lineCount: 100)
        let range = vp.visibleLineRange(scrollY: 100_000, visibleHeight: 1_000)

        #expect(range == 100 ..< 100)
    }

    @Test("computeViewport adds buffer")
    func computeViewportBuffer() {
        let vp = makeViewport(lineCount: 2000)
        let range = vp.computeViewport(scrollY: 16000, visibleHeight: 160)
        let visible = vp.visibleLineRange(scrollY: 16000, visibleHeight: 160)
        let buffer = vp.viewportBuffer(visibleLineCount: visible.count)
        let expectedStart = max(0, visible.lowerBound - buffer)
        let expectedEnd = min(2000, visible.upperBound + buffer)
        #expect(range.lowerBound == expectedStart)
        #expect(range.upperBound == expectedEnd)
    }

    @Test("viewport buffer is bounded and proportional")
    func viewportBufferBounds() {
        let vp = makeViewport(lineCount: 2000)

        #expect(vp.viewportBuffer(visibleLineCount: 10) == ViewportState.minimumViewportBuffer)
        #expect(vp.viewportBuffer(visibleLineCount: 70) == 140)
        #expect(vp.viewportBuffer(visibleLineCount: 200) == ViewportState.maximumViewportBuffer)
    }

    @Test("computeViewport clamps to bounds")
    func computeViewportClamp() {
        let vp = makeViewport(lineCount: 100)
        let range = vp.computeViewport(scrollY: 0, visibleHeight: 160)
        #expect(range.lowerBound == 0)
        #expect(range.upperBound == 90)
    }

    @Test("shouldUpdateViewport returns true initially")
    func shouldUpdateInitially() {
        let vp = makeViewport(lineCount: 100)
        #expect(vp.shouldUpdateViewport(scrollY: 0, visibleHeight: 160))
    }

    @Test("shouldUpdateViewport returns false with adequate margin")
    func shouldUpdateFalseAdequateMargin() {
        let vp = makeViewport(lineCount: 2000)
        vp.applyViewport(0 ..< 1000)
        #expect(!vp.shouldUpdateViewport(scrollY: 8000, visibleHeight: 160))
    }

    @Test("shouldUpdateViewport returns true when margin below hysteresis")
    func shouldUpdateTrueLowMargin() {
        let vp = makeViewport(lineCount: 2000)
        vp.applyViewport(0 ..< 480)
        #expect(vp.shouldUpdateViewport(scrollY: 7200, visibleHeight: 160))
    }

    @Test("applyViewport sets start and end")
    func applyViewport() {
        let vp = makeViewport(lineCount: 100)
        vp.applyViewport(10 ..< 50)
        #expect(vp.viewportStartLine == 10)
        #expect(vp.viewportEndLine == 50)
        #expect(vp.viewportLineCount == 40)
    }

    @Test("applyViewport clamps stale ranges to visual line count")
    func applyViewportClampsStaleRanges() {
        let vp = makeViewport(lineCount: 100)

        vp.applyViewport(9_000 ..< 9_500)

        #expect(vp.viewportStartLine == 100)
        #expect(vp.viewportEndLine == 100)
        #expect(vp.viewportText().isEmpty)
    }

    @Test("viewportText returns correct content")
    func viewportText() {
        let vp = makeViewport(lineCount: 10)
        vp.applyViewport(2 ..< 5)
        let text = vp.viewportText()
        #expect(text == "line 2\nline 3\nline 4")
    }

    @Test("viewportYOffset is start * lineHeight")
    func viewportYOffset() {
        let vp = makeViewport(lineCount: 100)
        vp.applyViewport(10 ..< 50)
        #expect(vp.viewportYOffset() == 160)
    }

    @Test("backingStoreLine adds viewport offset")
    func backingStoreLine() {
        let vp = makeViewport(lineCount: 100)
        vp.applyViewport(20 ..< 50)
        #expect(vp.backingStoreLine(forViewportLine: 0) == 20)
        #expect(vp.backingStoreLine(forViewportLine: 5) == 25)
    }

    @Test("viewportLine returns local index for in-viewport line")
    func viewportLineInRange() {
        let vp = makeViewport(lineCount: 100)
        vp.applyViewport(20 ..< 50)
        #expect(vp.viewportLine(forBackingStoreLine: 25) == 5)
    }

    @Test("viewportLine returns nil for out-of-viewport line")
    func viewportLineOutOfRange() {
        let vp = makeViewport(lineCount: 100)
        vp.applyViewport(20 ..< 50)
        #expect(vp.viewportLine(forBackingStoreLine: 10) == nil)
        #expect(vp.viewportLine(forBackingStoreLine: 50) == nil)
    }

    @Test("isLineInViewport returns correct values")
    func isLineInViewport() {
        let vp = makeViewport(lineCount: 100)
        vp.applyViewport(20 ..< 50)
        #expect(vp.isLineInViewport(25))
        #expect(!vp.isLineInViewport(10))
        #expect(!vp.isLineInViewport(50))
    }

    @Test("scrollY for line is line * lineHeight")
    func scrollYForLine() {
        let vp = makeViewport(lineCount: 100)
        #expect(vp.scrollY(forLine: 10) == 160)
        #expect(vp.scrollY(forLine: 0) == 0)
    }

    @Test("folded viewport maps only visible lines")
    func foldedViewportMapsVisibleLines() {
        let vp = makeViewport(lineCount: 8)
        vp.rebuildVisualLines(collapsedRegions: [EditorFoldRegion(startLine: 1, endLine: 4)])
        vp.applyViewport(0 ..< 4)

        #expect(vp.visualLineCount == 5)
        #expect(vp.viewportText() == "line 0\nline 1\nline 5\nline 6")
        #expect(vp.viewportLine(forBackingStoreLine: 3) == nil)
        #expect(vp.viewportLine(forBackingStoreLine: 5) == 2)
        #expect(vp.isLineFolded(3))
    }
}
