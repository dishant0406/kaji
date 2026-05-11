import Testing

@testable import Kaji

struct AskInlineAnnotationsExactTokenTests {
    @Test
    func exactAnnotationDoesNotStayActive() {
        let parsed = AskInlineAnnotations.parse("what is this project about :t:codex")

        #expect(parsed.activeAnnotation == nil)
        #expect(parsed.annotations[.provider] == "codex")
        #expect(parsed.prompt == "what is this project about")
    }

    @Test
    func exactHistoryAnnotationDoesNotStayActive() {
        let parsed = AskInlineAnnotations.parse("what is this :t:codex :h:session-id")

        #expect(parsed.activeAnnotation == nil)
        #expect(parsed.annotations[.provider] == "codex")
        #expect(parsed.annotations[.history] == "session-id")
        #expect(parsed.prompt == "what is this")
    }
}
