import Foundation
import Testing

@testable import Kaji

@Suite("EditorDecorationPolicy")
struct EditorDecorationPolicyTests {
    @Test("applies editor appearance only before first apply or after settings changed")
    func editorAppearanceApplicationPolicy() {
        #expect(EditorDecorationPolicy.shouldApplyEditorAppearance(
            hasAppliedAppearance: false,
            appearanceChanged: false
        ))
        #expect(EditorDecorationPolicy.shouldApplyEditorAppearance(
            hasAppliedAppearance: true,
            appearanceChanged: true
        ))
        #expect(!EditorDecorationPolicy.shouldApplyEditorAppearance(
            hasAppliedAppearance: true,
            appearanceChanged: false
        ))
    }

    @Test("limits matching bracket scans to a bounded distance")
    func matchingBracketScanDistancePolicy() {
        #expect(EditorDecorationPolicy.shouldContinueMatchingBracketScan(distanceUTF16: 0))
        #expect(EditorDecorationPolicy.shouldContinueMatchingBracketScan(
            distanceUTF16: EditorDecorationPolicy.maximumMatchingBracketScanDistanceUTF16
        ))
        #expect(!EditorDecorationPolicy.shouldContinueMatchingBracketScan(
            distanceUTF16: EditorDecorationPolicy.maximumMatchingBracketScanDistanceUTF16 + 1
        ))
    }

    @Test("active line rect uses viewport line position without text layout")
    func activeLineRect() {
        let rect = EditorDecorationPolicy.activeLineRect(
            lineY: 120,
            topInset: 4,
            width: 800,
            lineHeight: 18
        )

        #expect(rect.origin.x == 0)
        #expect(rect.origin.y == 124)
        #expect(rect.width == 800)
        #expect(rect.height == 18)
    }

    @Test("diagnostic gutter marker uses document line position")
    func diagnosticGutterMarkerRect() {
        let rect = EditorDecorationPolicy.diagnosticGutterMarkerRect(lineY: 300)

        #expect(rect.origin.x == 6)
        #expect(rect.origin.y == 305)
        #expect(rect.width == 6)
        #expect(rect.height == 6)
    }

    @Test("visible viewport invalidation only runs when viewport range changes")
    func visibleViewportInvalidationPolicy() {
        #expect(EditorDecorationPolicy.shouldInvalidateVisibleViewport(
            previousViewportRange: nil,
            currentViewportRange: 10 ..< 20
        ))
        #expect(!EditorDecorationPolicy.shouldInvalidateVisibleViewport(
            previousViewportRange: 10 ..< 20,
            currentViewportRange: 10 ..< 20
        ))
        #expect(EditorDecorationPolicy.shouldInvalidateVisibleViewport(
            previousViewportRange: 10 ..< 20,
            currentViewportRange: 12 ..< 22
        ))
    }

    @Test("decoration invalidation lines include active and bracket line deltas")
    func decorationInvalidationLines() {
        let lines = EditorDecorationPolicy.decorationInvalidationLines(
            previousActiveLine: 4,
            currentActiveLine: 6,
            previousBracketLines: [4, 10, -1],
            currentBracketLines: [6, 12]
        )

        #expect(lines == [4, 6, 10, 12])
    }

    @Test("visible decoration column limit includes visible width and tab padding")
    func visibleDecorationColumnLimit() {
        #expect(EditorDecorationPolicy.visibleDecorationColumnLimit(
            dirtyMaxX: 98,
            textOriginX: 10,
            unitWidth: 8,
            tabSize: 4
        ) == 15)
        #expect(EditorDecorationPolicy.visibleDecorationColumnLimit(
            dirtyMaxX: 4,
            textOriginX: 10,
            unitWidth: 8,
            tabSize: 4
        ) == 4)
    }

    @Test("indentation columns read NSString ranges and expand tabs")
    func indentationColumns() {
        let content = "root\n \t  child\nnext" as NSString
        let range = content.lineRange(for: NSRange(location: 5, length: 0))

        #expect(EditorDecorationPolicy.indentationColumns(
            in: content,
            lineRange: range,
            tabSize: 4,
            maximumColumns: 20
        ) == 6)
    }

    @Test("indentation columns stop at the visible column limit")
    func boundedIndentationColumns() {
        let content = (String(repeating: " ", count: 1000) + "value") as NSString

        #expect(EditorDecorationPolicy.indentationColumns(
            in: content,
            lineRange: NSRange(location: 0, length: content.length),
            tabSize: 4,
            maximumColumns: 12
        ) == 12)
    }

    @Test("matching bracket scan only runs when enabled and cursor line is visible")
    func matchingBracketScanPolicy() {
        #expect(EditorDecorationPolicy.shouldScanMatchingBrackets(
            activeLine: 5,
            viewportRange: 0 ..< 10,
            enabled: true
        ))
        #expect(!EditorDecorationPolicy.shouldScanMatchingBrackets(
            activeLine: 12,
            viewportRange: 0 ..< 10,
            enabled: true
        ))
        #expect(!EditorDecorationPolicy.shouldScanMatchingBrackets(
            activeLine: 5,
            viewportRange: 0 ..< 10,
            enabled: false
        ))
    }

    @Test("selection handling skips duplicate selection events for same backing store version")
    func selectionHandlingPolicy() {
        let range = NSRange(location: 4, length: 0)

        #expect(EditorDecorationPolicy.shouldHandleSelectionChange(
            previousRange: nil,
            currentRange: range,
            previousBackingStoreVersion: nil,
            currentBackingStoreVersion: 1
        ))
        #expect(!EditorDecorationPolicy.shouldHandleSelectionChange(
            previousRange: range,
            currentRange: range,
            previousBackingStoreVersion: 1,
            currentBackingStoreVersion: 1
        ))
        #expect(EditorDecorationPolicy.shouldHandleSelectionChange(
            previousRange: range,
            currentRange: range,
            previousBackingStoreVersion: 1,
            currentBackingStoreVersion: 2
        ))
    }

    @Test("matching bracket candidate policy avoids non bracket scans")
    func matchingBracketCandidatePolicy() {
        let pairs: [unichar: unichar] = [40: 41, 91: 93]
        let reversePairs: [unichar: unichar] = [41: 40, 93: 91]

        #expect(EditorDecorationPolicy.isMatchingBracketCandidate(40, openingPairs: pairs, closingPairs: reversePairs))
        #expect(EditorDecorationPolicy.isMatchingBracketCandidate(93, openingPairs: pairs, closingPairs: reversePairs))
        #expect(!EditorDecorationPolicy.isMatchingBracketCandidate(97, openingPairs: pairs, closingPairs: reversePairs))
    }

    @Test("filters fold regions to visible start lines")
    func visibleFoldRegions() {
        let regions = [
            EditorFoldRegion(startLine: 1, endLine: 3),
            EditorFoldRegion(startLine: 8, endLine: 9),
            EditorFoldRegion(startLine: 12, endLine: 14),
        ]

        #expect(EditorDecorationPolicy.visibleFoldRegions(regions, viewportRange: 5 ..< 10) == [
            EditorFoldRegion(startLine: 8, endLine: 9),
        ])
    }

    @Test("filters diagnostics to visible one-based lines")
    func visibleDiagnostics() {
        let diagnostics = [
            diagnostic(id: "a", line: 1),
            diagnostic(id: "b", line: 6),
            diagnostic(id: "c", line: 10),
        ]

        #expect(EditorDecorationPolicy.visibleDiagnostics(diagnostics, viewportRange: 5 ..< 10).map(\.id) == ["b", "c"])
    }

    @Test("skips duplicate diagnostics refresh after viewport update already refreshed it")
    func diagnosticsCommitRefreshPolicy() {
        #expect(!EditorDecorationPolicy.shouldRefreshDiagnosticsAfterViewportCommit(
            didRefreshDiagnosticsDuringViewportUpdate: true
        ))
        #expect(EditorDecorationPolicy.shouldRefreshDiagnosticsAfterViewportCommit(
            didRefreshDiagnosticsDuringViewportUpdate: false
        ))
    }

    @Test("finds visible search matches without scanning earlier lines")
    func visibleSearchMatchIndexes() {
        let matches = [
            searchMatch(line: 1),
            searchMatch(line: 3),
            searchMatch(line: 8),
            searchMatch(line: 10),
            searchMatch(line: 15),
        ]

        let visible = EditorDecorationPolicy.visibleSearchMatchIndexes(matches, viewportRange: 8 ..< 12)

        #expect(Array(visible) == [2, 3])
    }

    @Test("visible search match indexes handle empty and out of range viewports")
    func visibleSearchMatchIndexesEdges() {
        let matches = [searchMatch(line: 4), searchMatch(line: 9)]

        #expect(EditorDecorationPolicy.visibleSearchMatchIndexes([], viewportRange: 0 ..< 10).isEmpty)
        #expect(EditorDecorationPolicy.visibleSearchMatchIndexes(matches, viewportRange: 1 ..< 1).isEmpty)
        #expect(EditorDecorationPolicy.visibleSearchMatchIndexes(matches, viewportRange: 10 ..< 20).isEmpty)
        #expect(Array(EditorDecorationPolicy.visibleSearchMatchIndexes(matches, viewportRange: 0 ..< 5)) == [0])
    }

    private func diagnostic(id: String, line: Int) -> EditorDiagnostic {
        EditorDiagnostic(
            id: id,
            filePath: "/tmp/file.swift",
            relativePath: "file.swift",
            line: line,
            column: 1,
            severity: .warning,
            message: id,
            source: nil
        )
    }

    private func searchMatch(line: Int) -> TextBackingStore.SearchMatch {
        TextBackingStore.SearchMatch(lineIndex: line, range: NSRange(location: 0, length: 1))
    }
}
