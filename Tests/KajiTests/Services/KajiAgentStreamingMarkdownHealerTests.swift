import Testing

@testable import Kaji

struct KajiAgentStreamingMarkdownHealerTests {
    @Test
    func closesIncompleteStrongMarkerForLiveRendering() {
        let blocks = KajiAgentMarkdownParser.parse(KajiAgentStreamingMarkdownHealer.heal("This is **important"))

        #expect(blocks == [.paragraph("This is **important**")])
    }

    @Test
    func closesIncompleteInlineCodeForLiveRendering() {
        let healed = KajiAgentStreamingMarkdownHealer.heal("Run `swift test")

        #expect(healed == "Run `swift test`")
    }

    @Test
    func leavesOpenCodeFenceUntouched() {
        let content = "```swift\nlet value = 1"

        #expect(KajiAgentStreamingMarkdownHealer.heal(content) == content)
        #expect(KajiAgentMarkdownParser.parse(content) == [.code(language: "swift", text: "let value = 1")])
    }

    @Test
    func stripsIncompleteLinkBracketToAvoidRawMarkdownFlash() {
        let healed = KajiAgentStreamingMarkdownHealer.heal("See [architecture")

        #expect(healed == "See architecture")
    }
}
