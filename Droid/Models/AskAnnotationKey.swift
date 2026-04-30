import Foundation

enum AskAnnotationKey: String, CaseIterable, Hashable {
    case project = "p"
    case worktree = "wt"
    case provider = "t"
    case session = "s"

    var token: String {
        ":\(rawValue):"
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

    static func matches(_ raw: String) -> [Self] {
        let normalized = raw.lowercased()
        if normalized.isEmpty {
            return allCases
        }
        return allCases.filter { $0.rawValue.hasPrefix(normalized) }
    }
}
