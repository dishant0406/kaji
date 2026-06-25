import Foundation

@MainActor
final class BrowserSession {
    let key: WorktreeKey
    let state: BrowserPaneState
    private(set) var lastUsedAt = Date()
    private var closeHandler: (() -> Void)?

    init(key: WorktreeKey, state: BrowserPaneState) {
        self.key = key
        self.state = state
    }

    var controllers: BrowserControllerRegistry {
        state.controllers
    }

    func touch() {
        lastUsedAt = Date()
    }

    func registerControl(close: @escaping () -> Void) {
        closeHandler = close
        let sessionID = key.worktreeID.uuidString
        KajiBrowserControlRegistry.shared.register(
            sessionID: sessionID,
            state: state,
            controllers: controllers,
            close: close
        )
        _ = KajiBrowserControlBroker.shared.ensureStarted(sessionID: sessionID)
    }

    func unregisterControl() {
        KajiBrowserControlRegistry.shared.unregister(sessionID: key.worktreeID.uuidString)
        closeHandler = nil
    }

    func close() {
        unregisterControl()
        controllers.closeAll()
    }
}
