import Foundation

enum KajiAgentStreamingMarkdownHealer {
    static func heal(_ content: String) -> String {
        guard !content.isEmpty, !hasOpenCodeFence(content) else { return content }
        var value = content
        value = healIncompleteLink(value)
        value = closeUnpaired(marker: "**", in: value)
        value = closeUnpaired(marker: "__", in: value)
        value = closeUnpairedBacktick(in: value)
        value = closeUnpairedAsterisk(in: value)
        return value
    }

    static func hasOpenCodeFence(_ content: String) -> Bool {
        var fence: KajiAgentMarkdownFence?
        for line in content.markdownLinesKeepingNewlines() {
            if let active = fence {
                if active.closes(line) {
                    fence = nil
                }
                continue
            }
            if let next = KajiAgentMarkdownFence(line: line) {
                fence = next
            }
        }
        return fence != nil
    }

    private static func healIncompleteLink(_ content: String) -> String {
        if let range = content.range(of: "](", options: .backwards), !content[range.upperBound...].contains(")") {
            return content + ")"
        }
        guard let bracket = unmatchedOpeningBracket(in: content) else { return content }
        return String(content[..<bracket]) + String(content[content.index(after: bracket)...])
    }

    private static func unmatchedOpeningBracket(in content: String) -> String.Index? {
        var depth = 0
        var candidate: String.Index?
        var index = content.startIndex
        while index < content.endIndex {
            let character = content[index]
            if character == "[" {
                if index > content.startIndex, content[content.index(before: index)] == "!" {
                    index = content.index(after: index)
                    continue
                }
                depth += 1
                candidate = index
            } else if character == "]", depth > 0 {
                depth -= 1
                if depth == 0 {
                    candidate = nil
                }
            }
            index = content.index(after: index)
        }
        return candidate
    }

    private static func closeUnpaired(marker: String, in content: String) -> String {
        guard markerCount(marker, in: content).isMultiple(of: 2) == false else { return content }
        guard let range = content.range(of: marker, options: .backwards), range.upperBound < content.endIndex else { return content }
        return content + marker
    }

    private static func closeUnpairedBacktick(in content: String) -> String {
        guard singleBacktickCount(in: content).isMultiple(of: 2) == false else { return content }
        guard let index = content.lastIndex(of: "`"), content.index(after: index) < content.endIndex else { return content }
        return content + "`"
    }

    private static func closeUnpairedAsterisk(in content: String) -> String {
        let count = singleMarkerCount("*", in: content)
        guard count.isMultiple(of: 2) == false else { return content }
        guard let index = content.lastIndex(of: "*"), content.index(after: index) < content.endIndex else { return content }
        return content + "*"
    }

    private static func markerCount(_ marker: String, in content: String) -> Int {
        var count = 0
        var searchStart = content.startIndex
        while let range = content.range(of: marker, range: searchStart ..< content.endIndex) {
            count += 1
            searchStart = range.upperBound
        }
        return count
    }

    private static func singleBacktickCount(in content: String) -> Int {
        var count = 0
        var index = content.startIndex
        while index < content.endIndex {
            if content[index] == "`" {
                let run = content[index...].prefix { $0 == "`" }.count
                if run == 1 {
                    count += 1
                }
                index = content.index(index, offsetBy: run)
            } else {
                index = content.index(after: index)
            }
        }
        return count
    }

    private static func singleMarkerCount(_ marker: Character, in content: String) -> Int {
        var count = 0
        var index = content.startIndex
        while index < content.endIndex {
            if content[index] == marker {
                let run = content[index...].prefix { $0 == marker }.count
                if run == 1 {
                    count += 1
                }
                index = content.index(index, offsetBy: run)
            } else {
                index = content.index(after: index)
            }
        }
        return count
    }
}
