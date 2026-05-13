import Foundation

enum LanguagePackAssetValidator {
    static func validateAssets(for definition: LanguageDefinition) -> [String] {
        guard let syntax = definition.syntax else { return [] }
        var missing: [String] = []
        switch syntax.engine {
        case .treeSitter:
            if let queries = syntax.treeSitter?.queries {
                appendMissing(queries.highlights, definition: definition, missing: &missing)
                appendMissing(queries.injections, definition: definition, missing: &missing)
                appendMissing(queries.locals, definition: definition, missing: &missing)
                appendMissing(queries.folds, definition: definition, missing: &missing)
            }
            appendMissing(syntax.treeSitter?.parser.artifact, definition: definition, missing: &missing)
        case .textMate:
            appendMissing(syntax.textMate?.grammar, definition: definition, missing: &missing)
        case .builtInTokenizer,
             .tokenizer,
             .none:
            break
        }
        return missing
    }

    private static func appendMissing(_ path: String?, definition: LanguageDefinition, missing: inout [String]) {
        guard let path else { return }
        guard let url = LanguageAssetResolver.url(for: path, in: definition) else {
            missing.append(path)
            return
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            missing.append(path)
        }
    }
}
