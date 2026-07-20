import Foundation

enum KajiModalRoute: Identifiable, Hashable {
    case createPullRequest

    var id: String {
        switch self {
        case .createPullRequest:
            "create-pull-request"
        }
    }

    var animatedID: String? {
        switch self {
        case .createPullRequest:
            nil
        }
    }
}
