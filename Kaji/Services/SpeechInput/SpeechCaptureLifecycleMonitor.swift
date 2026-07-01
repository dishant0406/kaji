import AppKit
import Foundation

@MainActor
final class SpeechCaptureLifecycleMonitor {
    private var observers: [NSObjectProtocol] = []

    func start(onStop: @escaping @Sendable (SpeechCaptureStopReason) -> Void) {
        stop()
        let center = NotificationCenter.default
        observers = [
            center.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { _ in onStop(.appResignedActive) },
            center.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: nil,
                queue: .main
            ) { _ in onStop(.windowResignedKey) },
        ]
    }

    func stop() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }
}
