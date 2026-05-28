import Foundation

struct EditorViewportUndoCoalescingInput {
    let now: CFAbsoluteTime
    let lastTimestamp: CFAbsoluteTime?
    let coalesceInterval: CFTimeInterval
    let lastSelectionLine: Int?
    let lastSelectionColumn: Int?
    let nextSelectionLine: Int
    let nextSelectionColumn: Int
    let currentGroupEditCount: Int
}

enum EditorViewportUndoPolicy {
    static let maximumEditsPerGroup = 128

    static func shouldCoalesceEdit(
        _ input: EditorViewportUndoCoalescingInput,
        maximumEditsPerGroup: Int = Self.maximumEditsPerGroup
    ) -> Bool {
        guard input.currentGroupEditCount < maximumEditsPerGroup else { return false }
        guard let lastTimestamp = input.lastTimestamp else { return false }
        guard input.now - lastTimestamp <= input.coalesceInterval else { return false }
        return input.lastSelectionLine == input.nextSelectionLine && input.lastSelectionColumn == input.nextSelectionColumn
    }
}
