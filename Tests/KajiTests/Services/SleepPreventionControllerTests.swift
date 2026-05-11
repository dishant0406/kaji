import Foundation
import Testing

@testable import Kaji

@MainActor
struct SleepPreventionControllerTests {
    @Test
    func enablingStartsActivityAndPersistsPreference() {
        let suiteName = "SleepPreventionControllerTests.Enable.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let activityManager = RecordingSleepActivityManager()
        let systemSleepManager = RecordingSystemSleepAssertionManager()
        let controller = SleepPreventionController(
            defaults: defaults,
            activityManager: activityManager,
            systemSleepAssertionManager: systemSleepManager
        )

        #expect(!controller.isEnabled)
        #expect(activityManager.beginReasons.isEmpty)
        #expect(systemSleepManager.beginCount == 0)

        controller.setEnabled(true)

        #expect(controller.isEnabled)
        #expect(SleepPreventionPreferences.isEnabled(defaults: defaults))
        #expect(activityManager.beginReasons.count == 1)
        #expect(activityManager.endedActivities.isEmpty)
        #expect(systemSleepManager.beginCount == 1)
        #expect(systemSleepManager.endCount == 0)
        #expect(controller.systemSleepAssertionStatus == .active)
        #expect(!controller.isBatteryLidCloseEnabled)
    }

    @Test
    func disablingReleasesActivityAndPersistsPreference() {
        let suiteName = "SleepPreventionControllerTests.Disable.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        SleepPreventionPreferences.setEnabled(true, defaults: defaults)
        let activityManager = RecordingSleepActivityManager()
        let systemSleepManager = RecordingSystemSleepAssertionManager()
        let controller = SleepPreventionController(
            defaults: defaults,
            activityManager: activityManager,
            systemSleepAssertionManager: systemSleepManager
        )

        controller.setEnabled(false)
        controller.setEnabled(false)

        #expect(!controller.isEnabled)
        #expect(!SleepPreventionPreferences.isEnabled(defaults: defaults))
        #expect(activityManager.beginReasons.count == 1)
        #expect(activityManager.endedActivities == ["activity-1"])
        #expect(systemSleepManager.beginCount == 1)
        #expect(systemSleepManager.endCount == 1)
        #expect(controller.systemSleepAssertionStatus == .inactive)
    }

    @Test
    func unavailableCaffeinateStillEnablesIdleSleepPrevention() {
        let suiteName = "SleepPreventionControllerTests.Unavailable.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let activityManager = RecordingSleepActivityManager()
        let systemSleepManager = RecordingSystemSleepAssertionManager(beginStatus: .unavailable)
        let controller = SleepPreventionController(
            defaults: defaults,
            activityManager: activityManager,
            systemSleepAssertionManager: systemSleepManager
        )

        controller.setEnabled(true)

        #expect(controller.isEnabled)
        #expect(activityManager.beginReasons.count == 1)
        #expect(systemSleepManager.beginCount == 1)
        #expect(controller.systemSleepAssertionStatus == .unavailable)
        #expect(controller.detail.contains("caffeinate is unavailable"))
    }
}
