import Foundation

@MainActor
final class BrowserControllerRegistry {
    private var controllers: [UUID: BrowserWebController] = [:]

    func controller(for id: UUID) -> BrowserWebController {
        if let controller = controllers[id] {
            return controller
        }
        let controller = BrowserWebController()
        controllers[id] = controller
        return controller
    }

    func removeController(for id: UUID) {
        controllers[id]?.close()
        controllers.removeValue(forKey: id)
    }

    func closeAll() {
        controllers.values.forEach { $0.close() }
        controllers.removeAll()
    }
}
