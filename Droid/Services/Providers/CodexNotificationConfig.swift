import Foundation

enum CodexNotificationConfig {
    static let startMarker = "# droid-notify-start"
    static let endMarker = "# droid-notify-end"
    private static let originalMarker = "# droid-notify-original = "
    private static let passthroughFlag = "--passthrough-count"
    private static let blockedPassthroughExecutables = ["SkyComputerUseClient"]

    static func install(in content: String, scriptPath: String) -> String {
        var lines = content.components(separatedBy: .newlines)
        if let range = managedBlockRange(in: lines) {
            let passthrough = sanitizedPassthrough(originalNotifyArguments(in: Array(lines[range])))
            lines.removeSubrange(range)
            return installManagedBlock(
                in: lines,
                scriptPath: scriptPath,
                passthrough: passthrough ?? sanitizedPassthrough(existingNotifyArguments(in: lines))
            )
        }

        return installManagedBlock(
            in: lines,
            scriptPath: scriptPath,
            passthrough: sanitizedPassthrough(existingNotifyArguments(in: lines))
        )
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

    private static func managedBlock(scriptPath: String, passthrough: [String]?) -> [String] {
        let args = notifyArguments(scriptPath: scriptPath, passthrough: passthrough)
        var block = [startMarker]
        if let passthrough {
            block.append(originalMarker + tomlArray(passthrough))
        }
        block.append(notifyLine(arguments: args))
        block.append(endMarker)
        return block
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

    private static func existingNotifyArguments(in lines: [String]) -> [String]? {
        guard let range = notifyBlockRange(in: lines) else { return nil }
        return notifyArguments(in: Array(lines[range]))
    }

    private static func installManagedBlock(
        in lines: [String],
        scriptPath: String,
        passthrough: [String]?
    ) -> String {
        var lines = lines
        let replacement = managedBlock(scriptPath: scriptPath, passthrough: passthrough)

        if let range = notifyBlockRange(in: lines) {
            lines.replaceSubrange(range, with: replacement)
            return normalized(lines)
        }

        let tableIndex = lines.firstIndex { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("[") && trimmed.hasSuffix("]")
        }

        if let tableIndex {
            let prefix = Array(lines[..<tableIndex]).dropLastBlankLines()
            let suffix = Array(lines[tableIndex...]).dropFirstBlankLines()
            var merged = prefix
            if !merged.isEmpty {
                merged.append("")
            }
            merged.append(contentsOf: replacement)
            merged.append("")
            merged.append(contentsOf: suffix)
            return normalized(merged)
        }

        let existing = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !existing.isEmpty else {
            return replacement.joined(separator: "\n") + "\n"
        }

        return existing + "\n\n" + replacement.joined(separator: "\n") + "\n"
    }

    private static func originalNotifyArguments(in lines: [String]) -> [String]? {
        guard let line = lines.first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix(originalMarker) }) else {
            return nil
        }
        let value = line.trimmingCharacters(in: .whitespaces).dropFirst(originalMarker.count)
        return parseStringArray(String(value))
    }

    private static func notifyArguments(in lines: [String]) -> [String]? {
        let joined = lines.joined(separator: "\n")
        guard let notifyRange = joined.range(of: #"notify\s*=\s*\[[\s\S]*?\]"#, options: .regularExpression) else {
            return nil
        }
        let assignment = String(joined[notifyRange])
        guard let start = assignment.firstIndex(of: "["),
              let end = assignment.lastIndex(of: "]"),
              start < end
        else {
            return nil
        }
        return parseStringArray(String(assignment[start ... end]))
    }

    private static func notifyArguments(scriptPath: String, passthrough: [String]?) -> [String] {
        var args = ["/bin/bash", scriptPath]
        guard let passthrough, !passthrough.isEmpty else { return args }
        args += [passthroughFlag, String(passthrough.count)] + passthrough
        return args
    }

    private static func notifyLine(arguments: [String]) -> String {
        "notify = \(tomlArray(arguments))"
    }

    private static func tomlArray(_ values: [String]) -> String {
        let items = values.map { "\"\(tomlString($0))\"" }
        return "[" + items.joined(separator: ", ") + "]"
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

    private static func sanitizedPassthrough(_ arguments: [String]?) -> [String]? {
        guard let arguments, !arguments.isEmpty else { return nil }
        let containsBlockedExecutable = arguments.contains { argument in
            let executableName = URL(fileURLWithPath: argument).lastPathComponent
            return blockedPassthroughExecutables.contains(executableName)
        }
        return containsBlockedExecutable ? nil : arguments
    }
}

private extension [String] {
    func dropLastBlankLines() -> [String] {
        var lines = self
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }
        return lines
    }

    func dropFirstBlankLines() -> [String] {
        var lines = self
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeFirst()
        }
        return lines
    }
}
