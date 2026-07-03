import Foundation

enum KajiCodeGraphPromptTemplates {
    static let codeGraphFileName = "CODE_GRAPH.md"

    static var codeGraphDocument: String {
        [
            "# Code Graph",
            "",
            "This project may have a Kaji CodeGraph generated outside the repository.",
            "",
            "If the Kaji CodeGraph MCP server is installed, use its read-only tools before broad repository exploration:",
            "- `code_graph_status`",
            "- `code_graph_report`",
            "- `code_graph_search`",
            "- `code_graph_neighbors`",
            "- `code_graph_path`",
            "- `code_graph_hotspots`",
            "",
            "Use the graph for architecture, dependency, ownership, entrypoint, and codebase navigation questions.",
            "Use exact text search or normal repository tools for literal string matching.",
            "If the graph is missing or stale, continue with normal repository tools.",
            "Mention that the graph should be generated or updated from Kaji.",
        ].joined(separator: "\n")
    }

    static var agentsReference: String {
        "For architecture, dependency, ownership, entrypoint, or codebase navigation questions, see @\(codeGraphFileName) when present."
    }

    static var claudeReference: String {
        "For architecture, dependency, ownership, entrypoint, or codebase navigation questions, see @\(codeGraphFileName) when present."
    }
}
