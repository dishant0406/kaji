import AppKit

@MainActor
final class ViewportState {
    let backingStore: TextBackingStore

    private(set) var viewportStartLine = 0
    private(set) var viewportEndLine = 0
    private(set) var estimatedLineHeight: CGFloat = 16
    private(set) var documentVerticalPadding: CGFloat = 8
    private var visualLineMap = ViewportVisualLineMap()

    static let minimumViewportBuffer = 80
    static let maximumViewportBuffer = 180
    static let minimumScrollHysteresis = 30
    static let maximumScrollHysteresis = 80

    var viewportLineCount: Int { viewportEndLine - viewportStartLine }

    var totalDocumentHeight: CGFloat { contentHeight + documentVerticalPadding }

    var scrollableDocumentHeight: CGFloat { contentHeight }

    var visualLines: [Int] { visualLineMap.lines }

    var visualLineCount: Int {
        visualLineMap.count(backingLineCount: backingStore.lineCount)
    }

    init(backingStore: TextBackingStore) {
        self.backingStore = backingStore
        rebuildVisualLines(collapsedRegions: [])
    }

    func rebuildVisualLines(collapsedRegions: [EditorFoldRegion]) {
        visualLineMap.rebuild(backingLineCount: backingStore.lineCount, collapsedRegions: collapsedRegions)
        clampViewportToVisualLineCount()
    }

    func updateEstimatedLineHeight(font: NSFont) {
        estimatedLineHeight = ceil(NSLayoutManager().defaultLineHeight(for: font))
        if estimatedLineHeight < 1 {
            estimatedLineHeight = 16
        }
    }

    func updateDocumentPadding(topInset: CGFloat, bottomInset: CGFloat, safetyPadding: CGFloat = 0) {
        documentVerticalPadding = topInset + bottomInset + safetyPadding
    }

    func visibleLineRange(scrollY: CGFloat, visibleHeight: CGFloat) -> Range<Int> {
        let scrollY = clampedScrollY(scrollY: scrollY, visibleHeight: visibleHeight)
        let rawFirstVisible = max(0, Int(floor(scrollY / estimatedLineHeight)))
        let firstVisible = min(rawFirstVisible, visualLineCount)
        let lastVisible = min(
            visualLineCount,
            max(firstVisible, Int(ceil((scrollY + visibleHeight) / estimatedLineHeight)))
        )
        return firstVisible ..< max(firstVisible, lastVisible)
    }

    func computeViewport(scrollY: CGFloat, visibleHeight: CGFloat) -> Range<Int> {
        let visible = visibleLineRange(scrollY: scrollY, visibleHeight: visibleHeight)
        let buffer = viewportBuffer(visibleLineCount: visible.count)
        let start = max(0, visible.lowerBound - buffer)
        let end = min(visualLineCount, visible.upperBound + buffer)
        return start ..< max(start, end)
    }

    func shouldUpdateViewport(scrollY: CGFloat, visibleHeight: CGFloat) -> Bool {
        let visible = visibleLineRange(scrollY: scrollY, visibleHeight: visibleHeight)
        guard viewportStartLine < viewportEndLine else { return true }

        let hysteresis = scrollHysteresis(visibleLineCount: visible.count)
        let topMargin = visible.lowerBound - viewportStartLine
        let bottomMargin = viewportEndLine - visible.upperBound
        return topMargin < hysteresis || bottomMargin < hysteresis
    }

    func viewportBuffer(visibleLineCount: Int) -> Int {
        min(
            Self.maximumViewportBuffer,
            max(Self.minimumViewportBuffer, visibleLineCount * 2)
        )
    }

    func scrollHysteresis(visibleLineCount: Int) -> Int {
        min(
            Self.maximumScrollHysteresis,
            max(Self.minimumScrollHysteresis, visibleLineCount)
        )
    }

    func applyViewport(_ range: Range<Int>) {
        let start = min(max(0, range.lowerBound), visualLineCount)
        let end = min(max(start, range.upperBound), visualLineCount)
        viewportStartLine = start
        viewportEndLine = end
    }

    func viewportText() -> String {
        visualLineMap.text(startLine: viewportStartLine, endLine: viewportEndLine, backingStore: backingStore)
    }

    func viewportYOffset() -> CGFloat {
        CGFloat(viewportStartLine) * estimatedLineHeight
    }

    func backingStoreLine(forViewportLine localLine: Int) -> Int {
        visualLineMap.backingLine(
            forVisualLine: viewportStartLine + localLine,
            backingLineCount: backingStore.lineCount
        )
    }

    func viewportLine(forBackingStoreLine globalLine: Int) -> Int? {
        guard let visualLine = visualIndex(forBackingStoreLine: globalLine), visualLine >= viewportStartLine,
              visualLine < viewportEndLine
        else { return nil }
        return visualLine - viewportStartLine
    }

    func isLineInViewport(_ globalLine: Int) -> Bool {
        viewportLine(forBackingStoreLine: globalLine) != nil
    }

    func scrollY(forLine globalLine: Int) -> CGFloat {
        guard let visualLine = visualIndex(forBackingStoreLine: globalLine) else {
            return CGFloat(insertionVisualIndex(forBackingStoreLine: globalLine)) * estimatedLineHeight
        }
        return CGFloat(visualLine) * estimatedLineHeight
    }

    func maximumContentScrollY(visibleHeight: CGFloat) -> CGFloat {
        max(0, scrollableDocumentHeight - visibleHeight)
    }

    func clampedScrollY(scrollY: CGFloat, visibleHeight: CGFloat) -> CGFloat {
        min(max(0, scrollY), maximumContentScrollY(visibleHeight: visibleHeight))
    }

    func isLineFolded(_ globalLine: Int) -> Bool {
        visualLineMap.isFolded(globalLine)
    }

    private func visualIndex(forBackingStoreLine globalLine: Int) -> Int? {
        visualLineMap.visualIndex(forBackingLine: globalLine, backingLineCount: backingStore.lineCount)
    }

    private func insertionVisualIndex(forBackingStoreLine globalLine: Int) -> Int {
        visualLineMap.insertionVisualIndex(forBackingLine: globalLine, backingLineCount: backingStore.lineCount)
    }

    private func clampViewportToVisualLineCount() {
        viewportStartLine = min(viewportStartLine, visualLineCount)
        viewportEndLine = min(viewportEndLine, visualLineCount)
    }

    private var contentHeight: CGFloat {
        CGFloat(visualLineCount) * estimatedLineHeight
    }
}
