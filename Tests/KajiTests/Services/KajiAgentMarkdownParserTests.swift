import Testing

@testable import Kaji

struct KajiAgentMarkdownParserTests {
    @Test
    func parsesCodeFenceWithLanguage() throws {
        let blocks = KajiAgentMarkdownParser.parse("""
        ```swift
        let value = 1
        ```
        """)

        guard case let .code(language, text) = blocks.first else {
            Issue.record("Expected code block")
            return
        }
        #expect(language == "swift")
        #expect(text == "let value = 1")
    }

    @Test
    func parsesParagraphsListsAndQuotes() {
        let blocks = KajiAgentMarkdownParser.parse("""
        Intro

        - One
        - Two

        > Note
        """)

        #expect(blocks.count == 3)
        #expect(blocks[0].name == "paragraph")
        #expect(blocks[1].name == "bullets")
        #expect(blocks[2].name == "quote")
    }

    @Test
    func keepsInlineMarkdownInsideParagraphs() {
        let blocks = KajiAgentMarkdownParser.parse("**Clarifying Next.js Integration**")

        #expect(blocks == [.paragraph("**Clarifying Next.js Integration**")])
    }
}

private extension KajiAgentMarkdownBlock {
    var name: String {
        switch self {
        case .heading: "heading"
        case .paragraph: "paragraph"
        case .bullets: "bullets"
        case .ordered: "ordered"
        case .quote: "quote"
        case .code: "code"
        case .divider: "divider"
        }
    }
}
