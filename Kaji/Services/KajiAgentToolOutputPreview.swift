enum KajiAgentToolOutputPreview {
    private static let maxStoredOutputCharacters = 200_000

    static func make(from output: String, toolName: String, complete: Bool) -> KajiAgentToolOutputSummary {
        let storedOutput = capped(output)
        let lines = storedOutput.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let limit = limit(for: toolName)
        let previewLines = previewLines(from: lines, limit: limit, tail: toolName == "bash")
        let truncated = max(lines.count - previewLines.count, 0)
        let summary = summary(for: output, lineCount: lineCount(in: output), complete: complete)
        return KajiAgentToolOutputSummary(
            summary: summary,
            preview: previewLines.joined(separator: "\n"),
            fullOutput: storedOutput,
            truncatedLineCount: truncated
        )
    }

    private static func limit(for toolName: String) -> Int {
        switch toolName {
        case "bash": 10
        case "read": 12
        case "write",
             "edit",
             "ast_edit": 14
        default: 8
        }
    }

    private static func previewLines(from lines: [String], limit: Int, tail: Bool) -> [String] {
        guard lines.count > limit else { return lines }
        return tail ? Array(lines.suffix(limit)) : Array(lines.prefix(limit))
    }

    private static func summary(for output: String, lineCount: Int, complete: Bool) -> String {
        if lineCount > 1 { return complete ? "\(lineCount) lines" : "Streaming \(lineCount) lines" }
        if !complete { return output.isEmpty ? "Streaming" : "Streaming result" }
        return output.count > 120 ? "\(output.count) characters" : "1 line"
    }

    private static func lineCount(in output: String) -> Int {
        output.reduce(1) { count, character in character == "\n" ? count + 1 : count }
    }

    private static func capped(_ output: String) -> String {
        guard output.count > maxStoredOutputCharacters else { return output }
        let omitted = output.count - maxStoredOutputCharacters
        return String(output.prefix(maxStoredOutputCharacters)) + "\n\n... truncated \(omitted) characters"
    }
}

struct KajiAgentToolOutputSummary: Hashable {
    let summary: String
    let preview: String
    let fullOutput: String
    let truncatedLineCount: Int
}
