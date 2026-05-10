import Foundation

enum MCPRuntimeListParser {
    static func parseCodexList(_ output: String) -> [MCPServerRuntimeRecord] {
        rows(from: output).compactMap { columns in
            guard columns.count >= 4, columns[0] != "Name" else { return nil }
            let name = columns[0]
            let url = columns.count == 5 ? columns[1] : nil
            let auth = columns.last
            let status = columns.dropLast().last
            return MCPServerRuntimeRecord(
                name: name,
                status: status == "-" ? nil : status,
                authSummary: auth == "-" ? nil : auth,
                url: url == "-" ? nil : url,
                command: columns.count > 5 ? columns[1] : nil,
                toolNames: []
            )
        }
    }

    static func parseOpenCodeList(_ output: String) -> [MCPServerRuntimeRecord] {
        output.components(separatedBy: .newlines).compactMap { line in
            let clean = stripANSI(line).trimmingCharacters(in: .whitespaces)
            guard clean.contains("connected") || clean.contains("disconnected") else { return nil }
            let parts = clean.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard let name = parts.dropFirst().first(where: { $0 != "✓" && $0 != "✗" }) else { return nil }
            return MCPServerRuntimeRecord(
                name: name,
                status: clean.contains("connected") ? "connected" : "disconnected",
                authSummary: nil,
                url: nil,
                command: nil,
                toolNames: []
            )
        }
    }

    static func parseClaudeList(_ output: String) -> [MCPServerRuntimeRecord] {
        output.components(separatedBy: .newlines).compactMap { line in
            let clean = stripANSI(line).trimmingCharacters(in: .whitespaces)
            guard !clean.isEmpty, !clean.lowercased().contains("error") else { return nil }
            let parts = clean.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard let name = parts.first else { return nil }
            return MCPServerRuntimeRecord(
                name: name,
                status: parts.dropFirst().last,
                authSummary: nil,
                url: nil,
                command: nil,
                toolNames: []
            )
        }
    }

    private static func rows(from output: String) -> [[String]] {
        output.components(separatedBy: .newlines).compactMap { line in
            let trimmed = stripANSI(line).trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            return Regex.whitespaceColumns.split(trimmed).map { String($0).trimmingCharacters(in: .whitespaces) }
        }
    }

    private static func stripANSI(_ value: String) -> String {
        value.replacingOccurrences(of: #"\u{001B}\[[0-9;]*[A-Za-z]"#, with: "", options: .regularExpression)
    }
}

private enum Regex {
    static let whitespaceColumns = makeWhitespaceColumns()

    private static func makeWhitespaceColumns() -> NSRegularExpression {
        guard let regex = try? NSRegularExpression(pattern: #"\s{2,}"#) else {
            preconditionFailure("Invalid whitespace column regex")
        }
        return regex
    }
}

private extension NSRegularExpression {
    func split(_ value: String) -> [Substring] {
        let range = NSRange(value.startIndex ..< value.endIndex, in: value)
        var result = [Substring]()
        var lastIndex = value.startIndex
        for match in matches(in: value, range: range) {
            guard let matchRange = Range(match.range, in: value) else { continue }
            result.append(value[lastIndex ..< matchRange.lowerBound])
            lastIndex = matchRange.upperBound
        }
        result.append(value[lastIndex ..< value.endIndex])
        return result
    }
}
