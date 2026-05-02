import Foundation

enum AskAnnotationKey: String, CaseIterable, Hashable {
    case project = "p"
    case worktree = "wt"
    case provider = "t"
    case mode = "m"
    case history = "h"
    case skill = "s"
    case task = "task"
    case taskAdd = "ta"
    case taskEdit = "te"
    case taskDelete = "td"
    case projectAdd = "pa"
    case attach = "attach"

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
        case .task:
            "Task"
        case .taskAdd:
            "Task Add"
        case .taskEdit:
            "Task Edit"
        case .taskDelete:
            "Task Delete"
        case .projectAdd:
            "Project Add"
        case .attach:
            "Attach"
        }
    }

    static func matches(_ raw: String) -> [Self] {
        let normalized = raw.lowercased()
        if normalized.isEmpty {
            return allCases
        }
        if let exact = Self(rawValue: normalized) {
            return [exact]
        }
        return allCases.filter { $0.rawValue.hasPrefix(normalized) }
    }
}
