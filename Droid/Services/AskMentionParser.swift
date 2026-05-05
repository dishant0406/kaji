import Foundation

enum AskMentionParser {
    static func activeMention(in text: String) -> AskActiveMention? {
        guard let atIndex = text.lastIndex(of: "@") else { return nil }
        let suffix = text[text.index(after: atIndex)...]
        guard !suffix.contains(where: \.isWhitespace) else { return nil }
        return AskActiveMention(range: atIndex ..< text.endIndex, query: String(suffix))
    }

    static func replacingActiveMention(in text: String, mention: AskActiveMention, with path: String) -> String {
        var result = text
        result.replaceSubrange(mention.range, with: "@\(path)")
        return result
    }
}
