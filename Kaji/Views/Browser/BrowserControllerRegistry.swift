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
        let controller = controllers.removeValue(forKey: id)
        Task { @MainActor in
            await Task.yield()
            controller?.close()
        }
    }

    func closeAll() {
        let closingControllers = Array(controllers.values)
        controllers.removeAll()
        Task { @MainActor in
            await Task.yield()
            closingControllers.forEach { $0.close() }
        }
    }
}
