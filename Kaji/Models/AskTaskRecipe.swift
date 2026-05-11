import Foundation

struct AskTaskRecipe: Codable, Hashable, Identifiable {
    let id: String
    var name: String
    var prompt: String
    var isBuiltIn: Bool
    var projectID: UUID?
    var updatedAt: Date

    static let builtIns: [Self] = [
        .builtIn("fix-tests", "Fix failing tests", "Run the relevant tests, inspect failures, patch the root cause, and rerun the checks."),
        .builtIn(
            "review-diff",
            "Review current diff",
            "Review the current staged and unstaged changes. Prioritize bugs, regressions, and missing tests."
        ),
        .builtIn("explain-repo", "Explain this repo", "Explain this repository's architecture, workflows, and key files."),
        .builtIn("continue-session", "Continue previous session", "Continue the selected previous session and preserve its context."),
        .builtIn("implement-feature", "Implement feature", "Plan, implement, test, and summarize the requested feature."),
        .builtIn("debug-error", "Debug error", "Use the pasted logs or last error to find the root cause and fix it."),
        .builtIn("update-docs", "Update docs", "Update documentation to match the current code changes."),
        .builtIn("prepare-commit", "Prepare commit", "Summarize the current changes and suggest a concise commit message."),
    ]

    var isGlobal: Bool { projectID == nil }

    static func user(name: String, prompt: String, projectID: UUID?) -> Self {
        Self(id: UUID().uuidString, name: name, prompt: prompt, isBuiltIn: false, projectID: projectID, updatedAt: Date())
    }

    private static func builtIn(_ id: String, _ name: String, _ prompt: String) -> Self {
        Self(id: "builtin:\(id)", name: name, prompt: prompt, isBuiltIn: true, projectID: nil, updatedAt: .distantPast)
    }
}
