import Foundation

enum LanguagePackGrammarBuilder {
    static func grammar(for definition: LanguageDefinition) -> SyntaxGrammar? {
        guard let syntax = definition.syntax?.tokenizer else { return nil }
        var id = 0
        let blockComments = blockCommentRules(from: definition.configuration.comments?.blockComment, nextID: &id)
        let strings = syntax.strings.map { rule in
            id += 1
            return SyntaxGrammar.StringRule(
                id: id,
                open: rule.open,
                close: rule.close,
                escape: rule.escape,
                multiline: rule.multiline ?? false,
                scope: SyntaxScope.fromLanguagePack(rule.scope) ?? .string
            )
        }

        return SyntaxGrammar(
            name: definition.id,
            extensions: definition.extensions,
            caseSensitiveKeywords: syntax.caseSensitiveKeywords ?? true,
            lineComments: definition.configuration.comments?.lineComment.map { [$0] } ?? [],
            lineCommentScope: .comment,
            blockComments: blockComments,
            strings: strings,
            keywordGroups: keywordGroups(from: syntax.keywords),
            supportsNumbers: syntax.supportsNumbers ?? true,
            supportsHashDirectives: syntax.supportsHashDirectives ?? false,
            hashDirectiveScope: .preprocessor,
            supportsAtAttributes: syntax.supportsAtAttributes ?? false,
            atAttributeScope: .attribute,
            highlightFunctionCalls: syntax.highlightFunctionCalls ?? true,
            highlightAllCapsAsConstant: syntax.highlightAllCapsAsConstant ?? false,
            identifierStart: SyntaxGrammar.defaultIdentifierStart,
            identifierBody: SyntaxGrammar.defaultIdentifierBody
        )
    }

    private static func blockCommentRules(from blockComment: [String]?, nextID: inout Int) -> [SyntaxGrammar.BlockCommentRule] {
        guard let blockComment, blockComment.count == 2 else { return [] }
        nextID += 1
        return [SyntaxGrammar.BlockCommentRule(
            id: nextID,
            open: blockComment[0],
            close: blockComment[1],
            scope: .comment,
            nestable: false
        )]
    }

    private static func keywordGroups(from groups: [LanguageSyntaxDefinition.KeywordGroup]) -> [SyntaxGrammar.KeywordGroup] {
        groups.compactMap { group in
            guard let scope = SyntaxScope.fromLanguagePack(group.scope) else { return nil }
            return SyntaxGrammar.KeywordGroup(words: Set(group.words), scope: scope)
        }
    }
}
