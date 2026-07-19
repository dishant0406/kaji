import AppKit
import Foundation
import Testing

@testable import Kaji

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

    @Test
    func wakeNotificationReconcilesSleepPrevention() async throws {
        let suiteName = "SystemWakeCoordinatorTests.Power.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        SleepPreventionPreferences.setEnabled(true, defaults: defaults)
        let center = NotificationCenter()
        let manager = RecordingSystemSleepAssertionManager(reconcileStatuses: [.active, .failed])
        let controller = SleepPreventionController(
            defaults: defaults,
            assertionManager: manager,
            notificationCenter: NotificationCenter()
        )
        let coordinator = SystemWakeCoordinator(
            notificationCenter: center,
            onWillSleep: {},
            onDidWake: { controller.reconcile() }
        )

        coordinator.start()
        center.post(name: NSWorkspace.didWakeNotification, object: NSWorkspace.shared)
        try await Task.sleep(for: .milliseconds(50))

        #expect(manager.reconcileCount == 2)
        #expect(controller.systemSleepAssertionStatus == .failed)
    }

    @Test
    func defaultSleepWakeHandlersPreserveRunHistory() async throws {
        let store = AIActivityStore.shared
        store.reset()

        let paneID = UUID()
        store.start(providerID: "codex", paneID: paneID, projectID: UUID(), worktreeID: UUID())

        let coordinator = SystemWakeCoordinator(notificationCenter: NotificationCenter())

        coordinator.start()
        coordinator.stop()

        #expect(AgentRunStore.shared.runs.first?.status == .running)
        store.reset()
    }
}
