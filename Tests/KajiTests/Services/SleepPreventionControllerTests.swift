import AppKit
import Foundation
import Testing

@testable import Kaji

@MainActor
struct SleepPreventionControllerTests {
    @Test
    func enablingCreatesVerifiedAssertionAndPersistsIntent() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = RecordingSystemSleepAssertionManager()
        let controller = SleepPreventionController(defaults: defaults, assertionManager: manager)

        controller.setEnabled(true)

        #expect(controller.isEnabled)
        #expect(controller.isAssertionActive)
        #expect(controller.systemSleepAssertionStatus == .active)
        #expect(SleepPreventionPreferences.isEnabled(defaults: defaults))
        #expect(manager.beginCount == 1)
    }

    @Test
    func assertionFailureKeepsPersistedIntentAndReportsUnverifiedState() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = RecordingSystemSleepAssertionManager(beginStatus: .failed)
        let controller = SleepPreventionController(defaults: defaults, assertionManager: manager)

        controller.setEnabled(true)

        #expect(controller.isEnabled)
        #expect(!controller.isAssertionActive)
        #expect(controller.systemSleepAssertionStatus == .failed)
        #expect(SleepPreventionPreferences.isEnabled(defaults: defaults))
        #expect(controller.detail.contains("could not verify"))
    }

    @Test
    func disablingReleasesAssertionAndPersistsPreference() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        SleepPreventionPreferences.setEnabled(true, defaults: defaults)
        let manager = RecordingSystemSleepAssertionManager()
        let controller = SleepPreventionController(defaults: defaults, assertionManager: manager)

        controller.setEnabled(false)

        #expect(!controller.isEnabled)
        #expect(!controller.isAssertionActive)
        #expect(!SleepPreventionPreferences.isEnabled(defaults: defaults))
        #expect(manager.endCount == 1)
        #expect(controller.systemSleepAssertionStatus == .inactive)
    }

    @Test
    func persistedIntentIsRestoredAndReconciled() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        SleepPreventionPreferences.setEnabled(true, defaults: defaults)
        let manager = RecordingSystemSleepAssertionManager(reconcileStatuses: [.active])

        let controller = SleepPreventionController(defaults: defaults, assertionManager: manager)

        #expect(controller.isEnabled)
        #expect(controller.isAssertionActive)
        #expect(manager.reconcileCount == 1)
    }

    @Test
    func activationAndPowerSourceChangesReconcileAssertion() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        SleepPreventionPreferences.setEnabled(true, defaults: defaults)
        let center = NotificationCenter()
        let manager = RecordingSystemSleepAssertionManager(reconcileStatuses: [.active, .failed, .active])
        let controller = SleepPreventionController(
            defaults: defaults,
            assertionManager: manager,
            notificationCenter: center
        )

        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        await Task.yield()
        #expect(controller.systemSleepAssertionStatus == .failed)

        center.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        await Task.yield()
        #expect(controller.systemSleepAssertionStatus == .active)
        #expect(manager.reconcileCount == 3)
    }

    @Test
    func stopReleasesOnceAndRemovesLifecycleObservers() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        SleepPreventionPreferences.setEnabled(true, defaults: defaults)
        let center = NotificationCenter()
        let manager = RecordingSystemSleepAssertionManager()
        let controller = SleepPreventionController(
            defaults: defaults,
            assertionManager: manager,
            notificationCenter: center
        )

        controller.stop()
        controller.stop()
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        await Task.yield()

        #expect(manager.endCount == 1)
        #expect(manager.reconcileCount == 1)
        #expect(controller.systemSleepAssertionStatus == .inactive)
    }

    @Test
    func legacyLidClosePreferenceIsRemovedWithoutSystemMutation() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacyKey = "kaji.power.preventBatteryLidCloseSleep"
        defaults.set(true, forKey: legacyKey)

        _ = SleepPreventionController(
            defaults: defaults,
            assertionManager: RecordingSystemSleepAssertionManager()
        )

        #expect(defaults.object(forKey: legacyKey) == nil)
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "SleepPreventionControllerTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create isolated UserDefaults suite")
        }
        return (defaults, suiteName)
    }
}
