import Testing

@testable import Kaji

struct KajiAgentInlineSemanticParserTests {
    @Test
    func detectsInlineCodeFilePathsCommandsAndSymbols() {
        let tokens = KajiAgentInlineSemanticParser.tokens(from: "Run `swift test` in Kaji/Views/App.swift and open KajiAgentStore")

        #expect(tokens.contains(.inlineCode("swift test")))
        #expect(tokens.contains { token in
            if case let .filePath(value) = token { return value.contains("Kaji/Views/App.swift") }
            return false
        })
        #expect(tokens.contains { token in
            if case let .symbol(value) = token { return value == "KajiAgentStore" }
            return false
        })
    }

    @Test
    func parsesStrongEmphasisLinksAndImages() {
        let tokens = KajiAgentInlineSemanticParser.tokens(from: "**Bold** *Italic* [Docs](https://example.com) ![Alt](file.png)")

        #expect(tokens.contains(.strong("Bold")))
        #expect(tokens.contains(.emphasis("Italic")))
        #expect(tokens.contains(.link(title: "Docs", url: "https://example.com")))
        #expect(tokens.contains(.image(alt: "Alt", source: "file.png")))
    }
}
