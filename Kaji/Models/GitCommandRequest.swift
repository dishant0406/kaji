import Foundation

enum GitPaletteCommand: String, CaseIterable, Hashable {
    case git
    case branch
    case switchBranch = "switch"
    case checkout
    case commit

    var trigger: String {
        ":\(rawValue)"
    }

    var title: String {
        switch self {
        case .git:
            "Git"
        case .branch:
            "Branches"
        case .switchBranch:
            "Switch Branch"
        case .checkout:
            "Checkout"
        case .commit:
            "Commit"
        }
    }
}

struct GitCommandPaletteState: Hashable {
    let command: GitPaletteCommand
    let filter: String
}

struct GitCommandRequest: Identifiable, Hashable {
    let arguments: [String]
    let displayCommand: String
    let confirmationMessage: String?
    let blockedMessage: String?
    let refreshesRepository: Bool

    var id: String {
        displayCommand
    }

    var canRun: Bool {
        blockedMessage == nil
    }
}
