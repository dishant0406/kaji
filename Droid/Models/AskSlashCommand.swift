import Foundation

enum AskSlashCommand: String, CaseIterable, Hashable, Identifiable {
    case project
    case worktree
    case provider
    case session

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
