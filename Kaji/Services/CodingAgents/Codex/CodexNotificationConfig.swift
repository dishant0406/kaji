import Foundation

enum CodexNotificationConfig {
    static let startMarker = "# kaji-notify-start"
    static let endMarker = "# kaji-notify-end"
    private static let originalMarker = "# kaji-notify-original = "

    static func install(in content: String, scriptPath _: String) -> String {
        uninstall(from: content)
    }

    static func uninstall(from content: String) -> String {
        var lines = content.components(separatedBy: .newlines)
        guard let range = managedBlockRange(in: lines) else {
            return content
        }
        let original = originalNotifyArguments(in: Array(lines[range]))
        if let original {
            lines.replaceSubrange(range, with: [notifyLine(arguments: original)])
        } else {
            lines.removeSubrange(range)
        }
        return normalized(lines)
    }

    private static func managedBlockRange(in lines: [String]) -> Range<Int>? {
        guard let startIndex = lines.firstIndex(of: startMarker),
              let endIndex = lines[startIndex...].firstIndex(of: endMarker)
        else {
            return nil
        }
        return startIndex ..< (endIndex + 1)
    }

    private static func originalNotifyArguments(in lines: [String]) -> [String]? {
        guard let line = lines.first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix(originalMarker) }) else {
            return nil
        }
        let value = line.trimmingCharacters(in: .whitespaces).dropFirst(originalMarker.count)
        return parseStringArray(String(value))
    }

    private static func notifyLine(arguments: [String]) -> String {
        "notify = \(tomlArray(arguments))"
    }

    private static func tomlArray(_ values: [String]) -> String {
        let items = values.map { "\"\(tomlString($0))\"" }
        return "[" + items.joined(separator: ", ") + "]"
    }

    private static func normalized(_ lines: [String]) -> String {
        let joined = lines.joined(separator: "\n")
        let squashed = joined.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )
        let trimmed = squashed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "" : trimmed + "\n"
    }

    private static func tomlString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func parseStringArray(_ value: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: #""((?:\\.|[^"])*)""#) else {
            return nil
        }
        let range = NSRange(value.startIndex..., in: value)
        let matches = regex.matches(in: value, range: range)
        guard !matches.isEmpty else { return nil }
        return matches.compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: value)
            else {
                return nil
            }
            return value[range]
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
    }
}
