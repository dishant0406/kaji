import Foundation

enum AskAnnotationKey: String, CaseIterable, Hashable {
    case project = "p"
    case worktree = "wt"
    case provider = "t"
    case mode = "m"
    case history = "h"
    case skill = "s"

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
        case .mode:
            "Mode"
        case .history:
            "History"
        case .skill:
            "Skill"
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
