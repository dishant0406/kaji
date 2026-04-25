import CoreGraphics
import Foundation

enum MarkdownEditorAnchorMapper {
    static func focusLine(scrollY: CGFloat, visibleHeight: CGFloat, estimatedLineHeight: CGFloat, lineCount: Int) -> Int {
        guard lineCount > 0 else { return 1 }
        let lineHeight = max(1, estimatedLineHeight)
        let topY = max(0, scrollY)
        let zeroBased = Int(floor(topY / lineHeight))
        return min(max(zeroBased + 1, 1), lineCount)
    }

    static func snapshot(focusLine: Int, anchors: [MarkdownSyncAnchor]) -> MarkdownEditorAnchorSyncSnapshot {
        guard let active = activeAnchor(for: focusLine, anchors: anchors) else {
            return .empty
        }

        let clampedLine = min(max(focusLine, active.startLine), active.endLine)
        let span = active.endLine - active.startLine
        let progress: Double = if span <= 0 {
            0
        } else {
            Double(clampedLine - active.startLine) / Double(span)
        }

        return MarkdownEditorAnchorSyncSnapshot(activeAnchorID: active.id, localProgress: min(max(progress, 0), 1))
    }

    static func activeAnchor(for focusLine: Int, anchors: [MarkdownSyncAnchor]) -> MarkdownSyncAnchor? {
        guard !anchors.isEmpty else { return nil }

        let clampedLine = max(focusLine, 1)
        let insertionIndex = anchors.partitioningIndex { $0.startLine > clampedLine }

        if insertionIndex == 0 {
            return anchors[0]
        }

        let previousIndex = insertionIndex - 1
        let previous = anchors[previousIndex]

        if clampedLine <= previous.endLine {
            return previous
        }

        if insertionIndex >= anchors.count {
            return previous
        }

        let next = anchors[insertionIndex]
        let previousDistance = max(0, clampedLine - previous.endLine)
        let nextDistance = max(0, next.startLine - clampedLine)

        if nextDistance < previousDistance {
            return next
        }
        return previous
    }
}

private extension Array {
    func partitioningIndex(where shouldInsertBefore: (Element) -> Bool) -> Int {
        var low = 0
        var high = count
        while low < high {
            let mid = (low + high) / 2
            if shouldInsertBefore(self[mid]) {
                high = mid
            } else {
                low = mid + 1
            }
        }
        return low
    }
}
