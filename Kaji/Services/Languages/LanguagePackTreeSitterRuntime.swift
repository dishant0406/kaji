import Foundation
import SwiftTreeSitter

enum LanguagePackTreeSitterRuntime {
    static func canUseNativeParser(for definition: LanguageDefinition) -> Bool {
        LanguagePackNativeParserValidator.validatedParserURL(for: definition) != nil
    }

    @MainActor
    static func highlighter(for definition: LanguageDefinition) -> (any SyntaxHighlighting)? {
        guard let parserURL = LanguagePackNativeParserValidator.validatedParserURL(for: definition),
              let treeSitter = definition.syntax?.treeSitter,
              let queryPath = treeSitter.queries.highlights,
              let queryURL = LanguageAssetResolver.url(for: queryPath, in: definition),
              let language = DynamicTreeSitterParserLoader.language(from: parserURL, parserID: treeSitter.parser.id),
              let query = try? Query(language: language, url: queryURL)
        else { return nil }
        return TreeSitterSyntaxHighlighter(definition: definition, language: language, query: query)
    }
}
