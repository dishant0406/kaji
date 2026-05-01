import Foundation
import Testing

@testable import Droid

struct AskInlineAnnotationsTests {
    @Test
    func parseExtractsPromptAndExactAnnotations() {
        let parsed = AskInlineAnnotations.parse("what is this :p:muxy repo :t:codex about")

        #expect(parsed.prompt == "what is this repo about")
        #expect(parsed.annotations[.project] == "muxy")
        #expect(parsed.annotations[.provider] == "codex")
    }

    @Test
    func parseTracksActivePartialAnnotation() {
        let parsed = AskInlineAnnotations.parse("what is this :wt:ma")

        #expect(parsed.activeAnnotation?.key == .worktree)
        #expect(parsed.activeAnnotation?.value == "ma")
        #expect(parsed.prompt == "what is this")
    }

    @Test
    func parseTracksModeHistoryAndSkillAnnotations() {
        let parsed = AskInlineAnnotations.parse("fix this :m:new :h:abc :s:copywriting")

        #expect(parsed.annotations[.mode] == "new")
        #expect(parsed.annotations[.history] == "abc")
        #expect(parsed.annotations[.skill] == "copywriting")
        #expect(parsed.prompt == "fix this")
    }

    @Test
    func legacySessionAnnotationResolvesExactModeValues() {
        let parsed = AskInlineAnnotations.parse("fix this :s:new")

        #expect(parsed.annotations[.mode] == "new")
        #expect(parsed.activeAnnotation == nil)
        #expect(parsed.prompt == "fix this")
    }

    @Test
    func replacingActiveAnnotationKeepsRestOfQuery() {
        let updated = AskInlineAnnotations.replacingActiveAnnotation(
            in: "what is this :t:co repo",
            with: ":t:codex"
        )

        #expect(updated == "what is this :t:codex repo")
    }
}
