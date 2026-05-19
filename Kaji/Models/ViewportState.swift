import AppKit
import os

private let logger = Logger(subsystem: "app.kaji", category: "ViewportState")

@MainActor
final class ViewportState {
    let backingStore: TextBackingStore

    private(set) var viewportStartLine = 0
    private(set) var viewportEndLine = 0
    private(set) var estimatedLineHeight: CGFloat = 16
    private(set) var documentVerticalPadding: CGFloat = 8
    private(set) var visualLines: [Int] = []
    private var foldedLineSet: Set<Int> = []

    static let minimumViewportBuffer = 80
    static let maximumViewportBuffer = 180
    static let minimumScrollHysteresis = 30
    static let maximumScrollHysteresis = 80

    var viewportLineCount: Int { viewportEndLine - viewportStartLine }

    var totalDocumentHeight: CGFloat {
        CGFloat(visualLineCount) * estimatedLineHeight + documentVerticalPadding
    }

    var visualLineCount: Int {
        max(visualLines.count, 1)
    }

    init(backingStore: TextBackingStore) {
        self.backingStore = backingStore
        rebuildVisualLines(collapsedRegions: [])
    }

    func rebuildVisualLines(collapsedRegions: [EditorFoldRegion]) {
        var hidden = Set<Int>()
        for region in collapsedRegions where region.endLine > region.startLine {
            for line in (region.startLine + 1) ... region.endLine {
                hidden.insert(line)
            }
        }
        foldedLineSet = hidden
        visualLines = (0 ..< backingStore.lineCount).filter { !hidden.contains($0) }
        if visualLines.isEmpty { visualLines = [0] }
        viewportStartLine = min(viewportStartLine, visualLineCount)
        viewportEndLine = min(viewportEndLine, visualLineCount)
    }

    func updateEstimatedLineHeight(font: NSFont) {
        estimatedLineHeight = ceil(NSLayoutManager().defaultLineHeight(for: font))
        if estimatedLineHeight < 1 {
            estimatedLineHeight = 16
        }
    }

    func updateDocumentPadding(topInset: CGFloat, bottomInset: CGFloat, safetyPadding: CGFloat = 24) {
        documentVerticalPadding = topInset + bottomInset + safetyPadding
    }

    func visibleLineRange(scrollY: CGFloat, visibleHeight: CGFloat) -> Range<Int> {
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
        min(Self.maximumViewportBuffer, max(Self.minimumViewportBuffer, visibleLineCount * 2))
    }

    func scrollHysteresis(visibleLineCount: Int) -> Int {
        min(Self.maximumScrollHysteresis, max(Self.minimumScrollHysteresis, visibleLineCount))
    }

    func applyViewport(_ range: Range<Int>) {
        let start = min(max(0, range.lowerBound), visualLineCount)
        let end = min(max(start, range.upperBound), visualLineCount)
        viewportStartLine = start
        viewportEndLine = end
    }

    func viewportText() -> String {
        let start = min(max(0, viewportStartLine), visualLines.count)
        let end = min(max(start, viewportEndLine), visualLines.count)
        let lines = visualLines[start ..< end].map { backingStore.line(at: $0) }
        return lines.joined(separator: "\n")
    }

    func viewportYOffset() -> CGFloat {
        CGFloat(viewportStartLine) * estimatedLineHeight
    }

    func backingStoreLine(forViewportLine localLine: Int) -> Int {
        let visualLine = viewportStartLine + localLine
        guard visualLine >= 0, visualLine < visualLines.count else { return visualLines.last ?? 0 }
        return visualLines[visualLine]
    }

    func viewportLine(forBackingStoreLine globalLine: Int) -> Int? {
        guard let visualLine = visualLines.firstIndex(of: globalLine), visualLine >= viewportStartLine, visualLine < viewportEndLine else { return nil }
        return visualLine - viewportStartLine
    }

    func isLineInViewport(_ globalLine: Int) -> Bool {
        viewportLine(forBackingStoreLine: globalLine) != nil
    }

    func scrollY(forLine globalLine: Int) -> CGFloat {
        guard let visualLine = visualLines.firstIndex(of: globalLine) else {
            let closest = visualLines.lastIndex { $0 < globalLine } ?? 0
            return CGFloat(closest) * estimatedLineHeight
        }
        return CGFloat(visualLine) * estimatedLineHeight
    }

    func isLineFolded(_ globalLine: Int) -> Bool {
        foldedLineSet.contains(globalLine)
    }
}
