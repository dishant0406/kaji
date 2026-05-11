import AppKit
import Foundation

@MainActor
final class SystemWakeCoordinator {
    static let shared = SystemWakeCoordinator()

    private let notificationCenter: NotificationCenter
    private let onWillSleep: () -> Void
    private let onDidWake: () -> Void
    private var observers: [NSObjectProtocol] = []

    init(
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        onWillSleep: @escaping () -> Void = {
            AIActivityStore.shared.reset()
            CodexSessionMonitor.shared.stop()
        },
        onDidWake: @escaping () -> Void = {
            AIActivityStore.shared.reset()
            ResourceMonitorService.shared.restartIfRunning()
            CodexSessionMonitor.shared.restart()
        }
    ) {
        self.notificationCenter = notificationCenter
        self.onWillSleep = onWillSleep
        self.onDidWake = onDidWake
    }

    func start() {
        guard observers.isEmpty else { return }

        observers = [
            notificationCenter.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: NSWorkspace.shared,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleWillSleep()
                }
            },
            notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: NSWorkspace.shared,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleDidWake()
                }
            },
        ]
    }

    func stop() {
        for observer in observers {
            notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
    }

    private func handleWillSleep() {
        onWillSleep()
    }

    private func handleDidWake() {
        onDidWake()
    }
}
