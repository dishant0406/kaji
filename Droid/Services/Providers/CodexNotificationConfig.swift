import Foundation

enum CodexNotificationConfig {
    static let startMarker = "# droid-notify-start"
    static let endMarker = "# droid-notify-end"

    static func install(in content: String, scriptPath: String) -> String {
        let replacement = managedBlock(scriptPath: scriptPath)
        var lines = content.components(separatedBy: .newlines)

        if let range = managedBlockRange(in: lines) {
            lines.replaceSubrange(range, with: replacement)
            return normalized(lines)
        }

        if let range = notifyBlockRange(in: lines) {
            lines.replaceSubrange(range, with: replacement)
            return normalized(lines)
        }

        let existing = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !existing.isEmpty else {
            return replacement.joined(separator: "\n") + "\n"
        }

        return existing + "\n\n" + replacement.joined(separator: "\n") + "\n"
    }

    static func uninstall(from content: String) -> String {
        var lines = content.components(separatedBy: .newlines)
        guard let range = managedBlockRange(in: lines) else { return content }
        lines.removeSubrange(range)
        return normalized(lines)
    }

    private static func managedBlock(scriptPath: String) -> [String] {
        [
            startMarker,
            #"notify = ["\#(tomlString(scriptPath))"]"#,
            endMarker,
        ]
    }

    private static func managedBlockRange(in lines: [String]) -> Range<Int>? {
        guard let startIndex = lines.firstIndex(of: startMarker),
              let endIndex = lines[startIndex...].firstIndex(of: endMarker)
        else {
            return nil
        }
        return startIndex ..< (endIndex + 1)
    }

    private static func notifyBlockRange(in lines: [String]) -> Range<Int>? {
        for startIndex in lines.indices {
            let trimmed = lines[startIndex].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("notify"), trimmed.contains("=") else { continue }
            guard !trimmed.hasPrefix("#") else { continue }

            var depth = bracketDelta(for: trimmed)
            var endIndex = startIndex
            if depth <= 0, trimmed.contains("[") {
                return startIndex ..< (startIndex + 1)
            }

            while endIndex + 1 < lines.count {
                endIndex += 1
                depth += bracketDelta(for: lines[endIndex])
                if depth <= 0, lines[endIndex].contains("]") {
                    return startIndex ..< (endIndex + 1)
                }
            }

            return startIndex ..< (endIndex + 1)
        }

        return nil
    }

    private static func bracketDelta(for line: String) -> Int {
        line.reduce(into: 0) { result, character in
            if character == "[" {
                result += 1
            } else if character == "]" {
                result -= 1
            }
        }
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
}
