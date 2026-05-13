import Testing

@testable import Kaji

@Suite("EditorCursorPosition")
@MainActor
struct EditorCursorPositionTests {
    @Test("editor state clamps cursor metadata")
    func clampsCursorMetadata() {
        let state = EditorTabState(projectPath: "/tmp", filePath: "/tmp/test.swift")

        state.updateCursorPosition(line: -4, column: 0, selectionLength: -2)

        #expect(state.cursorLine == 1)
        #expect(state.cursorColumn == 1)
        #expect(state.cursorPosition.selectionLength == 0)
    }
}
