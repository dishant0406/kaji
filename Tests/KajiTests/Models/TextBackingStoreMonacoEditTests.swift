import Testing

@testable import Kaji

@Suite("TextBackingStore Monaco edits", .serialized)
@MainActor
struct TextBackingStoreMonacoEditTests {
    @Test("applies single line insert")
    func singleLineInsert() {
        let store = TextBackingStore()
        store.loadFromText("hello")
        store.applyMonacoEdits([edit(1, 6, 1, 6, " world")])
        #expect(store.fullText() == "hello world")
    }

    @Test("applies single line delete")
    func singleLineDelete() {
        let store = TextBackingStore()
        store.loadFromText("hello world")
        store.applyMonacoEdits([edit(1, 6, 1, 12, "")])
        #expect(store.fullText() == "hello")
    }

    @Test("applies multiline replacement")
    func multilineReplacement() {
        let store = TextBackingStore()
        store.loadFromText("alpha\nbeta\ngamma")
        store.applyMonacoEdits([edit(1, 3, 3, 4, "X\nY")])
        #expect(store.fullText() == "alX\nYma")
    }

    @Test("applies utf16 emoji range")
    func utf16EmojiRange() {
        let store = TextBackingStore()
        store.loadFromText("a😀b")
        store.applyMonacoEdits([edit(1, 2, 1, 4, "🙂")])
        #expect(store.fullText() == "a🙂b")
    }

    @Test("normalizes CRLF replacements")
    func normalizesCRLF() {
        let store = TextBackingStore()
        store.loadFromText("a\nd")
        store.applyMonacoEdits([edit(1, 2, 1, 2, "b\r\nc")])
        #expect(store.fullText() == "ab\nc\nd")
    }

    @Test("applies multiple edits from end to start")
    func multipleEdits() {
        let store = TextBackingStore()
        store.loadFromText("one\ntwo\nthree")
        store.applyMonacoEdits([
            edit(1, 1, 1, 4, "1"),
            edit(3, 1, 3, 6, "3"),
        ])
        #expect(store.fullText() == "1\ntwo\n3")
    }

    private func edit(_ startLine: Int, _ startColumn: Int, _ endLine: Int, _ endColumn: Int, _ text: String) -> MonacoTextEdit {
        MonacoTextEdit(
            range: MonacoRange(
                startLineNumber: startLine,
                startColumn: startColumn,
                endLineNumber: endLine,
                endColumn: endColumn
            ),
            text: text
        )
    }
}
