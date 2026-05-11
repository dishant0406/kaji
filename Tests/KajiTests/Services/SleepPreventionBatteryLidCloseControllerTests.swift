import Foundation
import Testing

@testable import Kaji

@MainActor
struct SleepPreventionBatteryLidCloseControllerTests {
    @Test
    func enablingBatteryLidCloseSleepRunsPmsetAndPersistsPreference() {
        let suiteName = "SleepPreventionControllerTests.BatteryLidClose.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let batteryLidCloseManager = RecordingBatteryLidCloseSleepManager()
        let controller = SleepPreventionController(
            defaults: defaults,
            activityManager: RecordingSleepActivityManager(),
            systemSleepAssertionManager: RecordingSystemSleepAssertionManager(),
            batteryLidCloseSleepManager: batteryLidCloseManager
        )

        controller.setBatteryLidCloseEnabled(true)

        #expect(controller.isBatteryLidCloseEnabled)
        #expect(SleepPreventionPreferences.batteryLidCloseIsEnabled(defaults: defaults))
        #expect(batteryLidCloseManager.beginCount == 1)
        #expect(batteryLidCloseManager.endCount == 0)
        #expect(controller.batteryLidCloseSleepStatus == .active)
    }

    @Test
    func failedBatteryLidCloseSleepEnableDoesNotPersistEnabledPreference() {
        let suiteName = "SleepPreventionControllerTests.BatteryLidCloseFailed.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let batteryLidCloseManager = RecordingBatteryLidCloseSleepManager(beginStatus: .failed)
        let controller = SleepPreventionController(
            defaults: defaults,
            activityManager: RecordingSleepActivityManager(),
            systemSleepAssertionManager: RecordingSystemSleepAssertionManager(),
            batteryLidCloseSleepManager: batteryLidCloseManager
        )

        controller.setBatteryLidCloseEnabled(true)

        #expect(!controller.isBatteryLidCloseEnabled)
        #expect(!SleepPreventionPreferences.batteryLidCloseIsEnabled(defaults: defaults))
        #expect(controller.batteryLidCloseSleepStatus == .failed)
        #expect(controller.batteryLidCloseDetail.contains("could not update pmset"))
    }

    @Test
    func disablingBatteryLidCloseSleepRestoresPmsetAndPersistsPreference() {
        let suiteName = "SleepPreventionControllerTests.BatteryLidCloseDisable.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        SleepPreventionPreferences.setBatteryLidCloseEnabled(true, defaults: defaults)
        let batteryLidCloseManager = RecordingBatteryLidCloseSleepManager()
        let controller = SleepPreventionController(
            defaults: defaults,
            activityManager: RecordingSleepActivityManager(),
            systemSleepAssertionManager: RecordingSystemSleepAssertionManager(),
            batteryLidCloseSleepManager: batteryLidCloseManager
        )

        controller.setBatteryLidCloseEnabled(false)

        #expect(!controller.isBatteryLidCloseEnabled)
        #expect(!SleepPreventionPreferences.batteryLidCloseIsEnabled(defaults: defaults))
        #expect(batteryLidCloseManager.beginCount == 1)
        #expect(batteryLidCloseManager.endCount == 1)
        #expect(controller.batteryLidCloseSleepStatus == .inactive)
    }
}
