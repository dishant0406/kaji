import Foundation
import Testing

@testable import Muxy

@Suite("MarkdownEditorAnchorMapper")
struct MarkdownEditorAnchorMapperTests {
    @Test("picks containing anchor and computes local progress")
    func containingAnchorAndProgress() {
        let anchors = [
            MarkdownSyncAnchor(id: "a", kind: .heading, startLine: 1, endLine: 1),
            MarkdownSyncAnchor(id: "b", kind: .paragraph, startLine: 3, endLine: 6),
            MarkdownSyncAnchor(id: "c", kind: .heading, startLine: 8, endLine: 8),
        ]

        #expect(MarkdownEditorAnchorMapper.snapshot(focusLine: 1, anchors: anchors) == MarkdownEditorAnchorSyncSnapshot(activeAnchorID: "a", localProgress: 0))
        #expect(MarkdownEditorAnchorMapper.snapshot(focusLine: 3, anchors: anchors) == MarkdownEditorAnchorSyncSnapshot(activeAnchorID: "b", localProgress: 0))
        #expect(MarkdownEditorAnchorMapper.snapshot(focusLine: 6, anchors: anchors) == MarkdownEditorAnchorSyncSnapshot(activeAnchorID: "b", localProgress: 1))
    }

    @Test("picks nearest anchor when focus line falls between anchors")
    func nearestAnchorBetweenBlocks() {
        let anchors = [
            MarkdownSyncAnchor(id: "a", kind: .heading, startLine: 1, endLine: 1),
            MarkdownSyncAnchor(id: "b", kind: .paragraph, startLine: 3, endLine: 6),
            MarkdownSyncAnchor(id: "c", kind: .heading, startLine: 8, endLine: 8),
        ]

        #expect(MarkdownEditorAnchorMapper.snapshot(focusLine: 2, anchors: anchors) == MarkdownEditorAnchorSyncSnapshot(activeAnchorID: "a", localProgress: 0))
        #expect(MarkdownEditorAnchorMapper.snapshot(focusLine: 7, anchors: anchors) == MarkdownEditorAnchorSyncSnapshot(activeAnchorID: "b", localProgress: 1))
    }

    @Test("computes focus line from top of viewport")
    func viewportFocusLine() {
        let focus = MarkdownEditorAnchorMapper.focusLine(scrollY: 0, visibleHeight: 100, estimatedLineHeight: 10, lineCount: 100)
        #expect(focus == 1)

        let nextVisibleLine = MarkdownEditorAnchorMapper.focusLine(scrollY: 25, visibleHeight: 100, estimatedLineHeight: 10, lineCount: 100)
        #expect(nextVisibleLine == 3)

        let clampedTop = MarkdownEditorAnchorMapper.focusLine(scrollY: -50, visibleHeight: 100, estimatedLineHeight: 10, lineCount: 10)
        #expect(clampedTop == 1)

        let clampedBottom = MarkdownEditorAnchorMapper.focusLine(scrollY: 10_000, visibleHeight: 100, estimatedLineHeight: 10, lineCount: 10)
        #expect(clampedBottom == 10)
    }
}
