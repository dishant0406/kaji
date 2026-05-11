import Foundation

@MainActor
final class BrowserSession {
    let key: WorktreeKey
    let state: BrowserPaneState
    let controllers = BrowserControllerRegistry()
    private(set) var lastUsedAt = Date()
    private var closeHandler: (() -> Void)?

    init(key: WorktreeKey, state: BrowserPaneState) {
        self.key = key
        self.state = state
    }

    func touch() {
        lastUsedAt = Date()
    }

    func registerControl(close: @escaping () -> Void) {
        closeHandler = close
        KajiBrowserControlRegistry.shared.register(
            sessionID: key.worktreeID.uuidString,
            state: state,
            controllers: controllers,
            close: close
        )
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
