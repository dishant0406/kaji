import Testing

@testable import Kaji

@Suite("Language registry source of truth")
@MainActor
struct LanguageRegistrySourceOfTruthTests {
    @Test("TypeScript resolves through language registry")
    func typescriptDefinition() {
        let definition = LanguageRegistry.shared.definition(forFile: "/tmp/App.tsx")

        #expect(definition?.id == "typescript")
        #expect(definition?.name == "TypeScript")
        #expect(definition?.syntax?.builtInTokenizer?.grammarID == "typescript")
        #expect(definition?.lsp?.command == "typescript-language-server")
    }

    @Test("JavaScript resolves through language registry")
    func javascriptDefinition() {
        let definition = LanguageRegistry.shared.definition(forFile: "/tmp/index.mjs")

        #expect(definition?.id == "javascript")
        #expect(definition?.name == "JavaScript")
        #expect(definition?.syntax?.builtInTokenizer?.grammarID == "javascript")
    }

    @Test("unknown files do not get syntax fallback")
    func noSyntaxFallbackForUnknownFiles() {
        #expect(LanguageRegistry.shared.definition(forFile: "/tmp/file.unknownext") == nil)
        #expect(SyntaxEngineRegistry.highlighter(forFile: "/tmp/file.unknownext") == nil)
    }
}
