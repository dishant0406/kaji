import Testing

@testable import Kaji

@Suite("InlineEditPromptBuilder")
struct InlineEditPromptBuilderTests {
    @Test("prompt includes file language instruction and selected code")
    func buildsPrompt() {
        let prompt = InlineEditPromptBuilder.prompt(
            filePath: "/tmp/App.swift",
            instruction: "  make it async  ",
            selectedCode: "func run() {}",
            languageID: "swift"
        )

        #expect(prompt.contains("Rewrite the selected code from App.swift."))
        #expect(prompt.contains("Language: swift"))
        #expect(prompt.contains("make it async"))
        #expect(prompt.contains("func run() {}"))
        #expect(prompt.contains("Return a drop-in replacement for the selection only."))
    }
}
