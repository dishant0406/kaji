import Foundation

struct EditorCursorPosition: Equatable {
    let line: Int
    let column: Int
    let selectionLength: Int

    static let initial = EditorCursorPosition(line: 1, column: 1, selectionLength: 0)
}
