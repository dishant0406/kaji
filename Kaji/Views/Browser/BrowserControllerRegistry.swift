import Foundation

@MainActor
final class BrowserControllerRegistry {
    private static let liveRegistries = NSHashTable<AnyObject>.weakObjects()

    private var controllers: [UUID: BrowserWebController] = [:]
    private var discardTask: Task<Void, Never>?

    init() {
        Self.liveRegistries.add(self)
    }

    deinit {
        discardTask?.cancel()
    }

    var controllerIDs: Set<UUID> {
        Set(controllers.keys)
    }

    func controller(for id: UUID) -> BrowserWebController {
        cancelScheduledDiscard()
        if let controller = controllers[id] {
            return controller
        }
        let controller = BrowserWebController()
        controllers[id] = controller
        return controller
    }

    func removeController(for id: UUID) {
        cancelScheduledDiscard()
        let controller = controllers.removeValue(forKey: id)
        Task { @MainActor in
            await Task.yield()
            controller?.close()
        }
    }

    func closeAll() {
        cancelScheduledDiscard()
        let closingControllers = Array(controllers.values)
        controllers.removeAll()
        Task { @MainActor in
            await Task.yield()
            closingControllers.forEach { $0.close() }
        }
    }

    func closeAllImmediately() {
        cancelScheduledDiscard()
        closeAllImmediatelyWithoutCancellingDiscard()
    }

    func scheduleDiscard(after delay: Duration = BrowserInactiveDiscardPolicy.defaultDelay) {
        discardTask?.cancel()
        discardTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.closeAllImmediatelyWithoutCancellingDiscard()
            self.discardTask = nil
        }
    }

    func cancelScheduledDiscard() {
        discardTask?.cancel()
        discardTask = nil
    }

    private func closeAllImmediatelyWithoutCancellingDiscard() {
        let closingControllers = Array(controllers.values)
        controllers.removeAll()
        closingControllers.forEach { $0.close() }
    }

    func retainControllers(for retainedIDs: Set<UUID>) {
        cancelScheduledDiscard()
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
        if active {
            cancelScheduledDiscard()
        }
        controllers.values.forEach { $0.setActive(active) }
    }

    static func closeAllRegisteredImmediately() {
        for registry in liveRegistries.allObjects.compactMap({ $0 as? BrowserControllerRegistry }) {
            registry.closeAllImmediately()
        }
    }
}
