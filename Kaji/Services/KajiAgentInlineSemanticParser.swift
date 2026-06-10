import Foundation

enum KajiAgentInlineSemanticParser {
    static func tokens(from text: String) -> [KajiAgentInlineToken] {
        mergeAdjacentText(tokens(from: text, start: text.startIndex, end: text.endIndex))
    }

    private static func tokens(from text: String, start: String.Index, end: String.Index) -> [KajiAgentInlineToken] {
        var tokens: [KajiAgentInlineToken] = []
        var cursor = start
        var plainStart = start

        func flushPlain(upTo index: String.Index) {
            guard plainStart < index else { return }
            tokens.append(contentsOf: semanticTokens(fromPlainText: String(text[plainStart ..< index])))
        }

        while cursor < end {
            if let parsed = parseToken(in: text, at: cursor, end: end) {
                flushPlain(upTo: cursor)
                tokens.append(parsed.token)
                cursor = parsed.end
                plainStart = cursor
            } else {
                cursor = text.index(after: cursor)
            }
        }
        flushPlain(upTo: end)
        return tokens
    }

    private struct ParsedToken {
        let token: KajiAgentInlineToken
        let end: String.Index
    }

    private struct BracketedToken {
        let label: String
        let url: String
        let end: String.Index
    }

    private static func parseToken(in text: String, at index: String.Index, end: String.Index) -> ParsedToken? {
        if hasPrefix("![", in: text, at: index, end: end),
           let parsed = bracketedToken(in: text, at: index, end: end, image: true)
        {
            return ParsedToken(token: .image(alt: parsed.label, source: parsed.url), end: parsed.end)
        }
        if text[index] == "[", let parsed = bracketedToken(in: text, at: index, end: end, image: false) {
            return ParsedToken(token: .link(title: parsed.label, url: parsed.url), end: parsed.end)
        }
        if hasPrefix("**", in: text, at: index, end: end), let parsed = delimited(in: text, at: index, end: end, marker: "**") {
            return ParsedToken(token: .strong(parsed.content), end: parsed.end)
        }
        if hasPrefix("__", in: text, at: index, end: end), let parsed = delimited(in: text, at: index, end: end, marker: "__") {
            return ParsedToken(token: .strong(parsed.content), end: parsed.end)
        }
        if text[index] == "*", let parsed = delimited(in: text, at: index, end: end, marker: "*") {
            return ParsedToken(token: .emphasis(parsed.content), end: parsed.end)
        }
        if text[index] == "_", let parsed = delimited(in: text, at: index, end: end, marker: "_") {
            return ParsedToken(token: .emphasis(parsed.content), end: parsed.end)
        }
        if text[index] == "`", let parsed = delimited(in: text, at: index, end: end, marker: "`") {
            return ParsedToken(token: .inlineCode(parsed.content), end: parsed.end)
        }
        return nil
    }

    private static func bracketedToken(
        in text: String,
        at index: String.Index,
        end: String.Index,
        image: Bool
    ) -> BracketedToken? {
        let labelStart = image ? text.index(index, offsetBy: 2) : text.index(after: index)
        guard labelStart <= end,
              let labelEnd = text[labelStart ..< end].firstIndex(of: "]"),
              text.index(after: labelEnd) < end,
              text[text.index(after: labelEnd)] == "("
        else { return nil }
        let urlStart = text.index(labelEnd, offsetBy: 2)
        guard urlStart <= end, let urlEnd = text[urlStart ..< end].firstIndex(of: ")") else { return nil }
        return BracketedToken(
            label: String(text[labelStart ..< labelEnd]),
            url: String(text[urlStart ..< urlEnd]),
            end: text.index(after: urlEnd)
        )
    }

    private static func delimited(
        in text: String,
        at index: String.Index,
        end: String.Index,
        marker: String
    ) -> (content: String, end: String.Index)? {
        let contentStart = text.index(index, offsetBy: marker.count)
        guard contentStart < end,
              let closing = text[contentStart ..< end].range(of: marker)?.lowerBound,
              closing > contentStart
        else { return nil }
        return (String(text[contentStart ..< closing]), text.index(closing, offsetBy: marker.count))
    }

    private static func hasPrefix(_ prefix: String, in text: String, at index: String.Index, end: String.Index) -> Bool {
        guard let upper = text.index(index, offsetBy: prefix.count, limitedBy: end) else { return false }
        return text[index ..< upper] == prefix
    }

    private static func semanticTokens(fromPlainText text: String) -> [KajiAgentInlineToken] {
        let words = text.splitKeepingSeparators()
        return words.map { word in
            let trimmed = word.trimmingCharacters(in: .punctuationCharacters)
            if isFilePath(trimmed) { return .filePath(word) }
            if isCommand(trimmed) { return .command(word) }
            if isSymbol(trimmed) { return .symbol(word) }
            return .text(word)
        }
    }

    private static func isFilePath(_ value: String) -> Bool {
        value.contains("/") || value.range(
            of: #"[A-Za-z0-9_\-]+\.(swift|ts|tsx|js|jsx|json|md|yml|yaml|toml|sh|zsh|py|rb|go|rs|c|h|cpp)(:\d+){0,2}$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isCommand(_ value: String) -> Bool {
        ["swift", "git", "npm", "pnpm", "yarn", "bun", "scripts/checks.sh", "make", "xcodebuild"].contains(value)
    }

    private static func isSymbol(_ value: String) -> Bool {
        value.hasSuffix("()") || value.range(of: #"^[A-Z][A-Za-z0-9_]+$"#, options: .regularExpression) != nil
    }

    private static func mergeAdjacentText(_ tokens: [KajiAgentInlineToken]) -> [KajiAgentInlineToken] {
        var merged: [KajiAgentInlineToken] = []
        for token in tokens {
            if case let .text(text) = token, case let .text(last)? = merged.last {
                merged[merged.count - 1] = .text(last + text)
            } else {
                merged.append(token)
            }
        }
        return merged
    }
}

private extension String {
    func splitKeepingSeparators() -> [String] {
        var values: [String] = []
        var current = ""
        for character in self {
            current.append(character)
            if character.isWhitespace {
                values.append(current)
                current = ""
            }
        }
        if !current.isEmpty { values.append(current) }
        return values
    }
}
