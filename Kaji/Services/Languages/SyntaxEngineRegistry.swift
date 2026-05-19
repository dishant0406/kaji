import Foundation

@MainActor
enum SyntaxEngineRegistry {
    static func highlighter(forFile filePath: String) -> (any SyntaxHighlighting)? {
        guard let definition = LanguageRegistry.shared.definition(forFile: filePath),
              let syntax = definition.syntax
        else {
            return nil
        }

        switch syntax.engine {
        case .builtInTokenizer:
            guard let grammarID = syntax.builtInTokenizer?.grammarID,
                  let grammar = SyntaxLanguageRegistry.grammar(forLanguageID: grammarID)
            else { return nil }
            return SyntaxHighlighter(grammar: grammar)
        case .tokenizer:
            guard let grammar = LanguagePackGrammarBuilder.grammar(for: definition) else {
                return nil
            }
            return SyntaxHighlighter(grammar: grammar)
        case .treeSitter:
            if let highlighter = LanguagePackTreeSitterRuntime.highlighter(for: definition) {
                return highlighter
            }
            if let grammar = LanguagePackGrammarBuilder.grammar(for: definition) {
                return SyntaxHighlighter(grammar: grammar)
            }
            return nil
        case .textMate:
            return nil
        case .none:
            return nil
        }
    }

}
