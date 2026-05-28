import Foundation
import SwiftTreeSitter

@MainActor
final class TreeSitterSyntaxHighlighter: SyntaxHighlighting {
    let grammar: SyntaxGrammar

    private let language: Language
    private let query: Query
    private let lineHighlighter: SyntaxHighlighter
    private var cachedText = ""
    private var cachedTokens: [Int: [TokenSpan]] = [:]
    private var usesLineHighlighter = false

    static let maximumTreeSitterUTF16Length = 500_000

    init(definition: LanguageDefinition, language: Language, query: Query) {
        let grammar = LanguagePackGrammarBuilder.grammar(for: definition) ?? SyntaxGrammar(
            name: definition.id,
            extensions: definition.extensions,
            caseSensitiveKeywords: true,
            lineComments: definition.configuration.comments?.lineComment.map { [$0] } ?? [],
            lineCommentScope: .comment,
            blockComments: [],
            strings: [],
            keywordGroups: [],
            supportsNumbers: false,
            supportsHashDirectives: false,
            hashDirectiveScope: .preprocessor,
            supportsAtAttributes: false,
            atAttributeScope: .attribute,
            highlightFunctionCalls: false,
            highlightAllCapsAsConstant: false,
            identifierStart: SyntaxGrammar.defaultIdentifierStart,
            identifierBody: SyntaxGrammar.defaultIdentifierBody
        )
        self.grammar = grammar
        self.language = language
        self.query = query
        self.lineHighlighter = SyntaxHighlighter(grammar: grammar)
    }

    func reset() {
        cachedText = ""
        cachedTokens.removeAll(keepingCapacity: false)
        lineHighlighter.reset()
        usesLineHighlighter = false
    }

    func invalidate(fromLine index: Int) {
        cachedTokens.removeAll(keepingCapacity: false)
        lineHighlighter.invalidate(fromLine: index)
    }

    func tokens(forLine line: Int) -> [TokenSpan]? {
        if usesLineHighlighter {
            return lineHighlighter.tokens(forLine: line)
        }
        return cachedTokens[line]
    }

    func applyEdit(
        startLine: Int,
        oldLineCount: Int,
        newLineCount: Int,
        backingStore: TextBackingStore
    ) -> SyntaxHighlighter.EditOutcome {
        guard !shouldUseLineHighlighterForEdit(for: backingStore) else {
            activateLineHighlighter()
            return lineHighlighter.applyEdit(
                startLine: startLine,
                oldLineCount: oldLineCount,
                newLineCount: newLineCount,
                backingStore: backingStore
            )
        }
        deactivateLineHighlighter()
        rebuild(from: backingStore)
        return .updated
    }

    func spans(
        in range: Range<Int>,
        lineStartOffsets: [Int],
        backingStore: TextBackingStore
    ) -> [SyntaxHighlighter.AppliedSpan] {
        guard !shouldUseLineHighlighter(for: backingStore) else {
            activateLineHighlighter()
            return lineHighlighter.spans(
                in: range,
                lineStartOffsets: lineStartOffsets,
                backingStore: backingStore
            )
        }
        deactivateLineHighlighter()
        rebuild(from: backingStore)
        var spans: [SyntaxHighlighter.AppliedSpan] = []
        for globalLine in range {
            let localIndex = globalLine - range.lowerBound
            guard localIndex >= 0, localIndex < lineStartOffsets.count else { continue }
            let lineOffset = lineStartOffsets[localIndex]
            for token in cachedTokens[globalLine] ?? [] {
                spans.append(SyntaxHighlighter.AppliedSpan(
                    range: NSRange(location: lineOffset + token.location, length: token.length),
                    scope: token.scope
                ))
            }
        }
        return spans
    }

    private func shouldUseLineHighlighter(for backingStore: TextBackingStore) -> Bool {
        backingStore.utf16LengthExceeds(Self.maximumTreeSitterUTF16Length)
    }

    private func shouldUseLineHighlighterForEdit(for backingStore: TextBackingStore) -> Bool {
        shouldUseLineHighlighter(for: backingStore)
            || TreeSitterEditHighlightPolicy.shouldUseLineHighlighterForEdit(utf16Length: backingStore.utf16Length)
    }

    private func activateLineHighlighter() {
        guard !usesLineHighlighter else { return }
        cachedText = ""
        cachedTokens.removeAll(keepingCapacity: false)
        usesLineHighlighter = true
    }

    private func deactivateLineHighlighter() {
        guard usesLineHighlighter else { return }
        lineHighlighter.reset()
        usesLineHighlighter = false
    }

    private func rebuild(from backingStore: TextBackingStore) {
        let text = backingStore.fullText()
        guard text != cachedText else { return }
        cachedText = text
        cachedTokens.removeAll(keepingCapacity: true)
        let lineStarts = lineStartOffsets(in: text)
        let parser = Parser()
        guard (try? parser.setLanguage(language)) != nil,
              let tree = parser.parse(text)
        else { return }
        let context = Predicate.Context(textProvider: text.predicateTextProvider)
        for namedRange in query.execute(in: tree).resolve(with: context).highlights() {
            let range = namedRange.range
            guard range.location >= 0, range.length > 0 else { continue }
            let line = lineIndex(for: range.location, lineStarts: lineStarts)
            let lineStart = line < lineStarts.count ? lineStarts[line] : 0
            cachedTokens[line, default: []].append(TokenSpan(
                location: range.location - lineStart,
                length: range.length,
                scope: Self.scope(for: namedRange.name)
            ))
        }
    }

    private func lineStartOffsets(in text: String) -> [Int] {
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

    private func lineIndex(for location: Int, lineStarts: [Int]) -> Int {
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

    private static func scope(for name: String) -> SyntaxScope {
        let normalized = name.split(separator: ".").first.map(String.init) ?? name
        return SyntaxScope.fromLanguagePack(normalized) ?? {
            switch normalized {
            case "operator": .op
            case "property": .variable
            default: .punctuation
            }
        }()
    }
}
