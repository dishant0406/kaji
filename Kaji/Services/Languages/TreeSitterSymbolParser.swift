import Foundation
import SwiftTreeSitter

enum TreeSitterSymbolParser {
    @MainActor
    static func symbols(in backingStore: TextBackingStore, definition: LanguageDefinition) -> [EditorSymbol]? {
        guard EditorStructuralAnalysisPolicy.allowsDocumentWideScan(backingStore) else { return nil }
        guard let parserURL = LanguagePackNativeParserValidator.validatedParserURL(for: definition),
              let treeSitter = definition.syntax?.treeSitter,
              let queryPath = treeSitter.queries.symbols,
              let queryURL = LanguageAssetResolver.url(for: queryPath, in: definition),
              FileManager.default.fileExists(atPath: queryURL.path),
              let language = DynamicTreeSitterParserLoader.language(from: parserURL, parserID: treeSitter.parser.id),
              let query = try? Query(language: language, url: queryURL)
        else { return nil }

        let text = backingStore.fullText()
        let parser = Parser()
        guard (try? parser.setLanguage(language)) != nil,
              let tree = parser.parse(text)
        else { return nil }

        let lineStarts = lineStartOffsets(in: text)
        let context = Predicate.Context(textProvider: text.predicateTextProvider)
        return query.execute(in: tree)
            .resolve(with: context)
            .highlights()
            .compactMap { range in
                guard let kind = kind(for: range.name) else { return nil }
                let nsRange = range.range
                guard nsRange.location >= 0, nsRange.length > 0 else { return nil }
                let line = lineIndex(for: nsRange.location, lineStarts: lineStarts)
                let column = nsRange.location - (line < lineStarts.count ? lineStarts[line] : 0)
                let name = (text as NSString).substring(with: nsRange)
                return EditorSymbol(name: name, kind: kind, line: line, column: column)
            }
    }

    private static func kind(for capture: String) -> EditorSymbol.Kind? {
        if capture.contains("function") || capture.contains("method") { return .function }
        if capture.contains("class") || capture.contains("struct") || capture.contains("enum") || capture.contains("type") { return .type }
        if capture.contains("property") || capture.contains("field") || capture.contains("variable") { return .property }
        if capture.contains("section") || capture.contains("heading") { return .section }
        if capture.hasPrefix("symbol") { return .function }
        return nil
    }

    private static func lineStartOffsets(in text: String) -> [Int] {
        let ns = text as NSString
        var offsets = [0]
        var searchRange = NSRange(location: 0, length: ns.length)
        while searchRange.location < ns.length {
            let found = ns.range(of: "\n", options: [], range: searchRange)
            guard found.location != NSNotFound else { break }
            let next = found.location + found.length
            offsets.append(next)
            searchRange = NSRange(location: next, length: ns.length - next)
        }
        return offsets
    }

    private static func lineIndex(for location: Int, lineStarts: [Int]) -> Int {
        var low = 0
        var high = lineStarts.count - 1
        while low <= high {
            let mid = (low + high) / 2
            if lineStarts[mid] <= location {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return max(0, high)
    }
}
