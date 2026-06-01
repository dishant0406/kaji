enum KajiAgentToolOutputPreview {
    static func make(from output: String, toolName: String, complete: Bool) -> KajiAgentToolOutputSummary {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let limit = limit(for: toolName)
        let previewLines = previewLines(from: lines, limit: limit, tail: toolName == "bash")
        let truncated = max(lines.count - previewLines.count, 0)
        let summary = summary(for: output, lines: lines, complete: complete)
        return KajiAgentToolOutputSummary(
            summary: summary,
            preview: previewLines.joined(separator: "\n"),
            fullOutput: output,
            truncatedLineCount: truncated
        )
    }

    private static func limit(for toolName: String) -> Int {
        switch toolName {
        case "bash": 10
        case "read": 12
        case "write", "edit", "ast_edit": 14
        default: 8
        }
    }

    private static func previewLines(from lines: [String], limit: Int, tail: Bool) -> [String] {
        guard lines.count > limit else { return lines }
        return tail ? Array(lines.suffix(limit)) : Array(lines.prefix(limit))
    }

    private static func summary(for output: String, lines: [String], complete: Bool) -> String {
        if lines.count > 1 { return complete ? "\(lines.count) lines" : "Streaming \(lines.count) lines" }
        return output.count > 120 ? "\(output.count) characters" : output
    }
}

struct KajiAgentToolOutputSummary: Hashable {
    let summary: String
    let preview: String
    let fullOutput: String
    let truncatedLineCount: Int
}
