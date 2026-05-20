import Foundation

enum AskAnnotationKey: String, CaseIterable, Hashable {
    case project = "p"
    case worktree = "wt"
    case provider = "t"
    case mode = "m"
    case history = "h"
    case skill = "s"
    case task
    case taskAdd = "ta"
    case taskEdit = "te"
    case taskDelete = "td"
    case projectAdd = "pa"
    case diff
    case attach
    case execute = "x"
    case executeAdd = "xa"
    case executeEdit = "xe"
    case executeDelete = "xd"
    case bookmark = "b"
    case bookmarkFolder = "bf"

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
        case .diff:
            "Diff"
        case .attach:
            "Attach"
        case .execute:
            "Run Script"
        case .executeAdd:
            "Add Script"
        case .executeEdit:
            "Edit Script"
        case .executeDelete:
            "Delete Script"
        case .bookmark:
            "Bookmark"
        case .bookmarkFolder:
            "Bookmark Folder"
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
