import Foundation

struct AskActiveAnnotation {
    let key: AskAnnotationKey
    let value: String
    let range: Range<String.Index>
}

struct AskParsedInput {
    let prompt: String
    let annotations: [AskAnnotationKey: String]
    let activeAnnotation: AskActiveAnnotation?
}

enum AskInlineAnnotations {
    static func parse(_ text: String) -> AskParsedInput {
        let tokens = tokenRanges(in: text)
        let active: AskActiveAnnotation?
        if let range = tokens.last {
            let token = String(text[range])
            if let exact = parseExactToken(token), isResolvedStaticValue(key: exact.key, value: exact.value) {
                active = nil
            } else {
                active = parseActiveToken(text[range], range: range)
            }
        } else {
            active = nil
        }
        var annotations: [AskAnnotationKey: String] = [:]
        var promptParts: [String] = []

        for range in tokens {
            let token = String(text[range])
            if let parsed = parseExactToken(token) {
                annotations[parsed.key] = parsed.value
                continue
            }
            if parseActiveToken(Substring(token), range: range) != nil {
                continue
            }
            promptParts.append(token)
        }

        return AskParsedInput(
            prompt: promptParts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines),
            annotations: annotations,
            activeAnnotation: active
        )
    }

    static func replacingActiveAnnotation(in text: String, with replacement: String) -> String {
        guard let active = lastAnnotation(in: text) else { return text }
        var updated = text
        updated.replaceSubrange(active.range, with: replacement)
        let endIndex = updated.index(active.range.lowerBound, offsetBy: replacement.count)
        if endIndex == updated.endIndex || updated[endIndex].isWhitespace {
            return updated
        }
        updated.insert(" ", at: endIndex)
        return updated
    }

    private static func lastAnnotation(in text: String) -> AskActiveAnnotation? {
        tokenRanges(in: text).reversed().compactMap { parseActiveToken(text[$0], range: $0) }.first
    }

    private static func parseExactToken(_ token: String) -> (key: AskAnnotationKey, value: String)? {
        guard token.hasPrefix(":") else { return nil }
        let parts = token.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].isEmpty else { return nil }
        guard let key = annotationKey(raw: String(parts[1]), value: String(parts[2])) else { return nil }
        let value = String(parts[2]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return (key, value)
    }

    private static func parseActiveToken(_ token: Substring, range: Range<String.Index>) -> AskActiveAnnotation? {
        guard token.hasPrefix(":") else { return nil }
        let body = token.dropFirst()
        let parts = body.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard let rawPrefix = parts.first else { return nil }
        let matches = AskAnnotationKey.matches(String(rawPrefix))
        guard matches.count == 1, let key = matches.first else { return nil }
        let value = parts.count > 1 ? String(parts[1]) : ""
        return .init(key: key, value: value, range: range)
    }

    private static func tokenRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var currentStart: String.Index?
        var index = text.startIndex

        while index < text.endIndex {
            if text[index].isWhitespace {
                if let start = currentStart {
                    ranges.append(start ..< index)
                    currentStart = nil
                }
            } else if currentStart == nil {
                currentStart = index
            }
            index = text.index(after: index)
        }

        if let start = currentStart {
            ranges.append(start ..< text.endIndex)
        }

        return ranges
    }

    private static func isResolvedStaticValue(key: AskAnnotationKey, value: String) -> Bool {
        switch key {
        case .provider:
            AskProvider.resolveAnnotation(value) != nil
        case .mode:
            AskSessionMode.resolveAnnotation(value) != nil
        case .history,
             .skill,
             .task,
             .taskAdd,
             .taskEdit,
             .taskDelete,
             .projectAdd,
             .attach:
            false
        case .project,
             .worktree:
            false
        }
    }

    private static func annotationKey(raw: String, value: String) -> AskAnnotationKey? {
        let normalized = raw.lowercased()
        if normalized == "s", AskSessionMode.resolveAnnotation(value) != nil {
            return .mode
        }
        return AskAnnotationKey(rawValue: normalized)
    }
}
