import Testing

@testable import Kaji

@Suite("TextBackingStore streaming edges", .serialized)
@MainActor
struct TextBackingStoreStreamingTests {
    @Test("appendText continues unterminated trailing line without duplication")
    func appendContinuesTrailingLine() {
        let store = TextBackingStore()
        store.loadFromText("alpha")

        store.appendText(" beta")
        store.appendText(" gamma")
        store.finishLoading()

        #expect(store.lineCount == 1)
        #expect(store.fullText() == "alpha beta gamma")
    }

    @Test("appendText continues a partial line after a previous newline chunk")
    func appendContinuesPartialLineAfterNewlineChunk() {
        let store = TextBackingStore()
        store.loadFromText("head")

        store.appendText("\npartial")
        store.appendText(" tail\nnext")
        store.finishLoading()

        #expect(store.lineCount == 3)
        #expect(store.fullText() == "head\npartial tail\nnext")
    }

    @Test("utf16LengthExceeds counts line separators without joining text")
    func utf16LengthExceeds() {
        let store = TextBackingStore()
        store.loadFromText("ab\ncd")

        #expect(store.utf16Length == 5)
        #expect(!store.utf16LengthExceeds(5))
        #expect(store.utf16LengthExceeds(4))
        #expect(store.utf16LengthExceeds(-1))
    }

    @Test("utf16 length stays current after line mutations")
    func utf16LengthTracksMutations() {
        let store = TextBackingStore()
        store.loadFromText("one\ntwo")

        store.appendText("\nthree")
        #expect(store.utf16Length == store.fullText().utf16.count)
        _ = store.replaceLines(in: 1 ..< 2, with: ["TWO", "middle"])
        #expect(store.utf16Length == store.fullText().utf16.count)
        store.insertLines(["zero"], at: 0)
        #expect(store.utf16Length == store.fullText().utf16.count)
    }

    @Test("fullText reflects mutations after cached reads")
    func fullTextReflectsMutationsAfterCachedReads() {
        let store = TextBackingStore()
        store.loadFromText("one\ntwo")

        #expect(store.fullText() == "one\ntwo")
        store.appendText(" three")
        #expect(store.fullText() == "one\ntwo three")
        _ = store.replaceLines(in: 0 ..< 1, with: ["zero"])
        #expect(store.fullText() == "zero\ntwo three")
        store.insertLines(["middle"], at: 1)
        #expect(store.fullText() == "zero\nmiddle\ntwo three")
    }
}
