import Foundation

extension BrowserPane {
    func registerBrowserControl() {
        guard let sessionID else { return }
        KajiBrowserControlRegistry.shared.register(
            sessionID: sessionID,
            state: state,
            controllers: state.controllers,
            close: onClosePane
        )
        KajiBrowserControlBroker.shared.updateSession(sessionID)
    }

    func unregisterBrowserControl() {
        guard let sessionID else { return }
        KajiBrowserControlRegistry.shared.unregister(sessionID: sessionID)
    }
}
