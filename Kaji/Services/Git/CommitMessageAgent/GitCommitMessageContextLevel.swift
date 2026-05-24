import Foundation

enum GitCommitMessageContextLevel: String, CaseIterable, Hashable, Identifiable {
    case fast
    case medium
    case detailed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fast:
            "Fast"
        case .medium:
            "Medium"
        case .detailed:
            "Detailed"
        }
    }

    var detail: String {
        switch self {
        case .fast:
            "Single-line message with selected-file metadata"
        case .medium:
            "Concise message with focused diff context"
        case .detailed:
            "Detailed message with broader diff context"
        }
    }

    var outputInstructions: [String] {
        switch self {
        case .fast:
            [
                "Return a single-line commit message.",
            ]
        case .medium:
            [
                "Return a concise commit message.",
                "Use a short body only when it adds useful context.",
            ]
        case .detailed:
            [
                "Return a detailed commit message.",
                "Use a subject, a blank line, and a body.",
                "The body should explain the main user-visible or technical changes.",
                "Keep the body concise and grounded in the inventory.",
            ]
        }
    }

    var snippetPolicy: GitCommitSnippetPolicy? {
        switch self {
        case .fast:
            nil
        case .medium:
            GitCommitSnippetPolicy(
                maxFiles: 4,
                maxCharacters: 6000,
                lineLimit: 120,
                contextLineCount: 1,
                rowLimit: 80,
                maxChangeWeight: 700
            )
        case .detailed:
            GitCommitSnippetPolicy(
                maxFiles: 10,
                maxCharacters: 20000,
                lineLimit: 240,
                contextLineCount: 3,
                rowLimit: 160,
                maxChangeWeight: 1600
            )
        }
    }
}

struct GitCommitSnippetPolicy: Hashable {
    let maxFiles: Int
    let maxCharacters: Int
    let lineLimit: Int
    let contextLineCount: Int
    let rowLimit: Int
    let maxChangeWeight: Int
}
