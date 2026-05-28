import CoreGraphics
import Foundation

enum EditorDecorationPolicy {
    static let maximumMatchingBracketScanDistanceUTF16 = 20000

    static func shouldContinueMatchingBracketScan(distanceUTF16: Int) -> Bool {
        distanceUTF16 <= maximumMatchingBracketScanDistanceUTF16
    }

    static func shouldApplyEditorAppearance(
        hasAppliedAppearance: Bool,
        appearanceChanged: Bool
    ) -> Bool {
        !hasAppliedAppearance || appearanceChanged
    }

    static func activeLineRect(
        lineY: CGFloat,
        topInset: CGFloat,
        width: CGFloat,
        lineHeight: CGFloat
    ) -> CGRect {
        CGRect(
            x: 0,
            y: lineY + topInset,
            width: width,
            height: lineHeight
        )
    }

    static func diagnosticGutterMarkerRect(lineY: CGFloat) -> CGRect {
        CGRect(x: 6, y: lineY + 5, width: 6, height: 6)
    }

    static func shouldInvalidateVisibleViewport(
        previousViewportRange: Range<Int>?,
        currentViewportRange: Range<Int>
    ) -> Bool {
        previousViewportRange != currentViewportRange
    }

    static func decorationInvalidationLines(
        previousActiveLine: Int?,
        currentActiveLine: Int,
        previousBracketLines: [Int],
        currentBracketLines: [Int]
    ) -> Set<Int> {
        var lines = Set<Int>()
        if let previousActiveLine {
            lines.insert(previousActiveLine)
        }
        lines.insert(currentActiveLine)
        previousBracketLines.forEach { lines.insert($0) }
        currentBracketLines.forEach { lines.insert($0) }
        return lines.filter { $0 >= 0 }
    }

    static func visibleDecorationColumnLimit(
        dirtyMaxX: CGFloat,
        textOriginX: CGFloat,
        unitWidth: CGFloat,
        tabSize: Int
    ) -> Int {
        guard unitWidth > 0 else { return 0 }
        let visibleWidth = max(0, dirtyMaxX - textOriginX)
        return max(0, Int(ceil(visibleWidth / unitWidth)) + max(1, tabSize))
    }

    static func indentationColumns(
        in content: NSString,
        lineRange: NSRange,
        tabSize: Int,
        maximumColumns: Int
    ) -> Int {
        guard lineRange.location >= 0,
              lineRange.location < content.length,
              lineRange.length > 0
        else { return 0 }
        let end = min(content.length, NSMaxRange(lineRange))
        var location = lineRange.location
        var columns = 0
        let tabSize = max(1, tabSize)
        let maximumColumns = max(0, maximumColumns)

        while location < end, columns <= maximumColumns {
            let unit = content.character(at: location)
            if unit == 32 {
                columns += 1
            } else if unit == 9 {
                columns += max(1, tabSize - columns % tabSize)
            } else {
                break
            }
            location += 1
        }

        return min(columns, maximumColumns)
    }

    static func shouldScanMatchingBrackets(activeLine: Int, viewportRange: Range<Int>, enabled: Bool) -> Bool {
        enabled && viewportRange.contains(activeLine)
    }

    static func shouldHandleSelectionChange(
        previousRange: NSRange?,
        currentRange: NSRange,
        previousBackingStoreVersion: Int?,
        currentBackingStoreVersion: Int
    ) -> Bool {
        previousRange != currentRange || previousBackingStoreVersion != currentBackingStoreVersion
    }

    static func isMatchingBracketCandidate(
        _ character: unichar,
        openingPairs: [unichar: unichar],
        closingPairs: [unichar: unichar]
    ) -> Bool {
        openingPairs[character] != nil || closingPairs[character] != nil
    }

    static func visibleFoldRegions(
        _ regions: [EditorFoldRegion],
        viewportRange: Range<Int>
    ) -> [EditorFoldRegion] {
        regions.filter { viewportRange.contains($0.startLine) }
    }

    static func visibleDiagnostics(
        _ diagnostics: [EditorDiagnostic],
        viewportRange: Range<Int>
    ) -> [EditorDiagnostic] {
        diagnostics.filter { viewportRange.contains($0.line - 1) }
    }

    static func visibleSearchMatchIndexes(
        _ matches: [TextBackingStore.SearchMatch],
        viewportRange: Range<Int>
    ) -> Range<Int> {
        guard !matches.isEmpty, !viewportRange.isEmpty else { return 0 ..< 0 }
        let start = lowerBoundSearchMatchIndex(matches, line: viewportRange.lowerBound)
        let end = lowerBoundSearchMatchIndex(matches, line: viewportRange.upperBound)
        return start ..< end
    }

    private static func lowerBoundSearchMatchIndex(
        _ matches: [TextBackingStore.SearchMatch],
        line: Int
    ) -> Int {
        var low = 0
        var high = matches.count
        while low < high {
            let mid = (low + high) / 2
            if matches[mid].lineIndex < line {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    static func shouldRefreshDiagnosticsAfterViewportCommit(
        didRefreshDiagnosticsDuringViewportUpdate: Bool
    ) -> Bool {
        !didRefreshDiagnosticsDuringViewportUpdate
    }
}
