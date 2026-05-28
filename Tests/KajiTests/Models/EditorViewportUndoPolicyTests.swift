import Testing
@testable import Kaji

@Suite("EditorViewportUndoPolicy")
struct EditorViewportUndoPolicyTests {
    @Test("coalesces adjacent edits within interval")
    func coalescesAdjacentEditsWithinInterval() {
        #expect(EditorViewportUndoPolicy.shouldCoalesceEdit(EditorViewportUndoCoalescingInput(
            now: 2,
            lastTimestamp: 1.5,
            coalesceInterval: 1,
            lastSelectionLine: 4,
            lastSelectionColumn: 12,
            nextSelectionLine: 4,
            nextSelectionColumn: 12,
            currentGroupEditCount: 10
        )))
    }

    @Test("starts a new group when coalesced edit count reaches the cap")
    func startsNewGroupAtEditCap() {
        #expect(!EditorViewportUndoPolicy.shouldCoalesceEdit(EditorViewportUndoCoalescingInput(
            now: 2,
            lastTimestamp: 1.5,
            coalesceInterval: 1,
            lastSelectionLine: 4,
            lastSelectionColumn: 12,
            nextSelectionLine: 4,
            nextSelectionColumn: 12,
            currentGroupEditCount: EditorViewportUndoPolicy.maximumEditsPerGroup
        )))
    }

    @Test("starts a new group for stale or disconnected edits")
    func startsNewGroupForStaleOrDisconnectedEdits() {
        #expect(!EditorViewportUndoPolicy.shouldCoalesceEdit(EditorViewportUndoCoalescingInput(
            now: 4,
            lastTimestamp: 1,
            coalesceInterval: 1,
            lastSelectionLine: 4,
            lastSelectionColumn: 12,
            nextSelectionLine: 4,
            nextSelectionColumn: 12,
            currentGroupEditCount: 10
        )))
        #expect(!EditorViewportUndoPolicy.shouldCoalesceEdit(EditorViewportUndoCoalescingInput(
            now: 2,
            lastTimestamp: 1.5,
            coalesceInterval: 1,
            lastSelectionLine: 4,
            lastSelectionColumn: 12,
            nextSelectionLine: 4,
            nextSelectionColumn: 13,
            currentGroupEditCount: 10
        )))
    }
}
