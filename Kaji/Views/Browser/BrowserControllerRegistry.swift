import Foundation

@MainActor
final class BrowserControllerRegistry {
    private var controllers: [UUID: BrowserWebController] = [:]

    var controllerIDs: Set<UUID> {
        Set(controllers.keys)
    }

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

    func retainControllers(for retainedIDs: Set<UUID>) {
        let closingControllers = controllers.filter { !retainedIDs.contains($0.key) }
        guard !closingControllers.isEmpty else { return }
        for id in closingControllers.keys {
            controllers[id] = nil
        }
        Task { @MainActor in
            await Task.yield()
            closingControllers.values.forEach { $0.close() }
        }
    }

    func setActive(_ active: Bool) {
        controllers.values.forEach { $0.setActive(active) }
    }
}
