import AppKit
import Foundation
import Testing

@testable import Droid

@MainActor
struct SystemWakeCoordinatorTests {
    @Test
    func wakeAndSleepNotificationsTriggerRestartHandlers() async throws {
        let center = NotificationCenter()
        var events: [String] = []
        let coordinator = SystemWakeCoordinator(
            notificationCenter: center,
            onWillSleep: { events.append("sleep") },
            onDidWake: { events.append("wake") }
        )

        coordinator.start()
        center.post(name: NSWorkspace.willSleepNotification, object: NSWorkspace.shared)
        center.post(name: NSWorkspace.didWakeNotification, object: NSWorkspace.shared)
        try await Task.sleep(for: .milliseconds(50))

        #expect(events == ["sleep", "wake"])
    }

    @Test
    func startIsIdempotent() async throws {
        let center = NotificationCenter()
        var wakeCount = 0
        let coordinator = SystemWakeCoordinator(
            notificationCenter: center,
            onWillSleep: {},
            onDidWake: { wakeCount += 1 }
        )

        coordinator.start()
        coordinator.start()
        center.post(name: NSWorkspace.didWakeNotification, object: NSWorkspace.shared)
        try await Task.sleep(for: .milliseconds(50))

        #expect(wakeCount == 1)
    }
}
