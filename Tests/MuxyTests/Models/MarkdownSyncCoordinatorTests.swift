import Foundation
import Testing

@testable import Muxy

@Suite("MarkdownSyncCoordinator")
struct MarkdownSyncCoordinatorTests {
    @Test("editor snapshot yields preview sync point")
    @MainActor
    func editorSnapshotToPreviewPoint() {
        let anchors = [
            MarkdownSyncAnchor(id: "a", kind: .heading, startLine: 1, endLine: 1),
            MarkdownSyncAnchor(id: "b", kind: .paragraph, startLine: 3, endLine: 6),
        ]

        let coordinator = MarkdownSyncCoordinator(now: { 0 })
        let snapshot = MarkdownEditorAnchorSyncSnapshot(activeAnchorID: "b", localProgress: 0.25)
        let output = coordinator.editorDidScroll(snapshot: snapshot, anchors: anchors)

        #expect(output.requestPreviewScroll == MarkdownSyncPoint(anchorID: "b", startLine: 3, endLine: 6, localProgress: 0.25))
        #expect(output.requestEditorScrollLine == nil)
    }

    @Test("preview sync point yields editor scroll line")
    @MainActor
    func previewPointToEditorLine() {
        let coordinator = MarkdownSyncCoordinator(now: { 0 })
        let point = MarkdownSyncPoint(anchorID: "x", startLine: 10, endLine: 20, localProgress: 0.5)
        let output = coordinator.previewDidScroll(point: point, totalLineCount: 500)

        #expect(output.requestPreviewScroll == nil)
        #expect(output.requestEditorScrollLine == 14)
    }

    @Test("suppresses preview echo after editor-driven request")
    @MainActor
    func suppressPreviewEcho() {
        var time: TimeInterval = 0
        let coordinator = MarkdownSyncCoordinator(now: { time })

        let anchors = [MarkdownSyncAnchor(id: "a", kind: .paragraph, startLine: 1, endLine: 10)]
        let snapshot = MarkdownEditorAnchorSyncSnapshot(activeAnchorID: "a", localProgress: 0.3)
        let output = coordinator.editorDidScroll(snapshot: snapshot, anchors: anchors)
        #expect(output.requestPreviewScroll != nil)

        time = 0.1
        let echo = output.requestPreviewScroll!
        let previewOutput = coordinator.previewDidScroll(point: echo, totalLineCount: 500)
        #expect(previewOutput.isEmpty)
    }

    @Test("reissues last preview request on relayout when editor is driver")
    @MainActor
    func relayoutReissue() {
        var time: TimeInterval = 0
        let coordinator = MarkdownSyncCoordinator(now: { time })

        let anchors = [MarkdownSyncAnchor(id: "a", kind: .paragraph, startLine: 1, endLine: 10)]
        let snapshot = MarkdownEditorAnchorSyncSnapshot(activeAnchorID: "a", localProgress: 0)
        _ = coordinator.editorDidScroll(snapshot: snapshot, anchors: anchors)

        time = 0.01
        #expect(coordinator.previewDidRelayout().isEmpty)

        time = 0.06
        let output = coordinator.previewDidRelayout()
        #expect(output.requestPreviewScroll == MarkdownSyncPoint(anchorID: "a", startLine: 1, endLine: 10, localProgress: 0))
    }
}
