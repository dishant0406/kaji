import Foundation

enum PullRequestRefreshPolicy {
    case automatic
    case force
    case preserveKnown

    var forceFresh: Bool {
        switch self {
        case .automatic:
            false
        case .force,
             .preserveKnown:
            true
        }
    }

    var preservesKnownInfo: Bool {
        self == .preserveKnown
    }
}
