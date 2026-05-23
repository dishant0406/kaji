import Foundation

enum GitDiffSource: Hashable {
    case workingTree
    case commit(hash: String, parentHash: String?)

    var isWorkingTree: Bool {
        self == .workingTree
    }

    var displayTitle: String {
        switch self {
        case .workingTree:
            "All Changes"
        case let .commit(hash, _):
            "Commit \(String(hash.prefix(7)))"
        }
    }
}
