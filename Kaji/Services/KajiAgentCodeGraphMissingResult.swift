import Foundation

enum KajiAgentCodeGraphMissingResult {
    static func report(reportURL: URL, graphURL: URL) -> KajiAgentToolResult {
        KajiAgentHostToolResult.error(message(kind: "report"), details: details(kind: "report", reportURL: reportURL, graphURL: graphURL))
    }

    static func graph(reportURL: URL, graphURL: URL) -> KajiAgentToolResult {
        KajiAgentHostToolResult.error(message(kind: "graph"), details: details(kind: "graph", reportURL: reportURL, graphURL: graphURL))
    }

    private static func message(kind: String) -> String {
        "No KajiCodeGraph \(kind) exists for the active worktree. Build the code graph from the Code Graph footer button first."
    }

    private static func details(kind: String, reportURL: URL, graphURL: URL) -> KajiAgentJSONValue {
        .object([
            "kind": .string("codeGraphMissing"),
            "missing": .string(kind),
            "missingGraph": .bool(true),
            "reportPath": .string(reportURL.path),
            "graphPath": .string(graphURL.path),
        ])
    }
}
