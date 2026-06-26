import Foundation

@MainActor
@Observable
final class KajiModalCoordinator {
    var route: KajiModalRoute?
    var createPullRequestState: VCSTabState?

    func present(_ route: KajiModalRoute) {
        self.route = route
    }

    func presentCreatePullRequest(state: VCSTabState) {
        createPullRequestState = state
        route = .createPullRequest
    }

    func dismiss() {
        route = nil
        createPullRequestState = nil
    }
}
