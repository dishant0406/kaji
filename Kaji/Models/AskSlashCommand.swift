import Foundation

enum AskSlashCommand: String, CaseIterable, Hashable, Identifiable {
    case project
    case worktree
    case provider
    case session
    case pullRequest = "pr"
    case bookmark
    case sleep
    case lid

    var id: String { rawValue }

    var trigger: String {
        "/\(rawValue)"
    }

    var title: String {
        switch self {
        case .project:
            "Project"
        case .worktree:
            "Worktree"
        case .provider:
            "Provider"
        case .session:
            "Session"
        case .pullRequest:
            "Create Pull Request"
        case .bookmark:
            "Bookmark Session"
        case .sleep:
            "Prevent Sleep"
        case .lid:
            "Closed-lid Sessions"
        }
    }

    var detail: String {
        switch self {
        case .project:
            "Choose the project that receives the prompt"
        case .worktree:
            "Target a specific worktree inside the selected project"
        case .provider:
            "Switch between Terminal and enabled coding agents"
        case .session:
            "Pick Best Match, Existing Session, or New Terminal"
        case .pullRequest:
            "Create a GitHub pull request for the current branch"
        case .bookmark:
            "Save visible coding-agent sessions for later"
        case .sleep:
            "Toggle macOS idle sleep prevention"
        case .lid:
            "Show live status and safe closed-lid actions"
        }
    }

    static func resolve(_ token: String) -> Self? {
        allCases.first { $0.rawValue == token.lowercased() }
    }

    static func matches(_ token: String) -> [Self] {
        let normalized = token.lowercased()
        if normalized.isEmpty {
            return allCases
        }
        return allCases.filter { $0.rawValue.hasPrefix(normalized) }
    }
}
