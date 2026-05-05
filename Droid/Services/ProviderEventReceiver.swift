import Foundation
import os

private let providerEventReceiverLogger = Logger(subsystem: "app.droid", category: "ProviderEventReceiver")

@MainActor
final class ProviderEventReceiver: NSObject {
    static let shared = ProviderEventReceiver()

    private var isListening = false

    override private init() {}

    func start() {
        guard !isListening else { return }
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleNotification(_:)),
            name: ProviderEvent.distributedName,
            object: ProviderEvent.distributedObject,
            suspensionBehavior: .deliverImmediately
        )
        isListening = true
    }

    func stop() {
        guard isListening else { return }
        DistributedNotificationCenter.default().removeObserver(
            self,
            name: ProviderEvent.distributedName,
            object: ProviderEvent.distributedObject
        )
        isListening = false
    }

    @objc
    private func handleNotification(_ notification: Notification) {
        guard let event = ProviderEvent(userInfo: notification.userInfo) else {
            providerEventReceiverLogger.warning("Ignored malformed provider event")
            return
        }

        DispatchQueue.main.async {
            ProviderEventDispatcher.dispatch(event)
        }
    }
}
