import Foundation

@MainActor
@Observable
final class KajiModalCoordinator {
    var route: KajiModalRoute?

    func present(_ route: KajiModalRoute) {
        self.route = route
    }

    func dismiss() {
        route = nil
    }
}
