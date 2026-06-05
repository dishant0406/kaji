import Foundation

@MainActor @Observable
final class SleepPreventionController {
    static let shared = SleepPreventionController()

    private let defaults: UserDefaults
    private let activityManager: SleepActivityManaging
    private let systemSleepAssertionManager: SystemSleepAssertionManaging
    private let batteryLidCloseSleepManager: BatteryLidCloseSleepManaging
    private var activity: NSObjectProtocol?

    private(set) var isEnabled: Bool
    private(set) var isBatteryLidCloseEnabled: Bool
    private(set) var systemSleepAssertionStatus: SystemSleepAssertionStatus = .inactive
    private(set) var batteryLidCloseSleepStatus: SystemSleepAssertionStatus = .inactive

    init(
        defaults: UserDefaults = .standard,
        activityManager: SleepActivityManaging = ProcessInfoSleepActivityManager(),
        systemSleepAssertionManager: SystemSleepAssertionManaging = CaffeinateSystemSleepAssertionManager(),
        batteryLidCloseSleepManager: BatteryLidCloseSleepManaging = PmsetBatteryLidCloseSleepManager()
    ) {
        self.defaults = defaults
        self.activityManager = activityManager
        self.systemSleepAssertionManager = systemSleepAssertionManager
        self.batteryLidCloseSleepManager = batteryLidCloseSleepManager
        isEnabled = SleepPreventionPreferences.isEnabled(defaults: defaults)
        isBatteryLidCloseEnabled = SleepPreventionPreferences.batteryLidCloseIsEnabled(defaults: defaults)
        updateActivity()
        updateBatteryLidCloseSleep()
    }

    var title: String {
        SleepPreventionDisplayText.title(isEnabled: isEnabled)
    }

    var detail: String {
        SleepPreventionDisplayText.detail(
            isEnabled: isEnabled,
            systemSleepAssertionStatus: systemSleepAssertionStatus
        )
    }

    var batteryLidCloseTitle: String {
        SleepPreventionDisplayText.batteryLidCloseTitle(isEnabled: isBatteryLidCloseEnabled)
    }

    var batteryLidCloseDetail: String {
        SleepPreventionDisplayText.batteryLidCloseDetail(
            isEnabled: isBatteryLidCloseEnabled,
            status: batteryLidCloseSleepStatus
        )
    }

    func toggle() {
        setEnabled(!isEnabled)
    }

    func toggleBatteryLidClose() {
        setBatteryLidCloseEnabled(!isBatteryLidCloseEnabled)
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        SleepPreventionPreferences.setEnabled(enabled, defaults: defaults)
        updateActivity()
    }

    func setBatteryLidCloseEnabled(_ enabled: Bool) {
        guard isBatteryLidCloseEnabled != enabled else { return }
        if enabled {
            Task { await enableBatteryLidCloseSleep() }
            return
        }
        releaseBatteryLidCloseSleep(preservePreference: false)
    }

    private func enableBatteryLidCloseSleep() async {
        batteryLidCloseSleepStatus = await batteryLidCloseSleepManager.begin()
        isBatteryLidCloseEnabled = batteryLidCloseSleepStatus == .active
        SleepPreventionPreferences.setBatteryLidCloseEnabled(isBatteryLidCloseEnabled, defaults: defaults)
    }

    func stop() {
        releaseActivity()
        releaseBatteryLidCloseSleep(preservePreference: true)
    }

    private func updateActivity() {
        guard isEnabled else {
            releaseActivity()
            return
        }
        guard activity == nil else { return }
        activity = activityManager.begin(reason: "Kaji is running long-lived terminal and agent sessions.")
        systemSleepAssertionStatus = systemSleepAssertionManager.begin()
    }

    private func releaseActivity() {
        guard let activity else { return }
        activityManager.end(activity)
        systemSleepAssertionManager.end()
        systemSleepAssertionStatus = systemSleepAssertionManager.status
        self.activity = nil
    }

    private func updateBatteryLidCloseSleep() {
        guard isBatteryLidCloseEnabled else { return }
        Task { await applyBatteryLidCloseSleep() }
    }

    private func applyBatteryLidCloseSleep() async {
        batteryLidCloseSleepStatus = await batteryLidCloseSleepManager.begin()
        isBatteryLidCloseEnabled = batteryLidCloseSleepStatus == .active
        SleepPreventionPreferences.setBatteryLidCloseEnabled(isBatteryLidCloseEnabled, defaults: defaults)
    }

    private func releaseBatteryLidCloseSleep(preservePreference: Bool) {
        let shouldPreservePreference = preservePreference && isBatteryLidCloseEnabled
        Task {
            batteryLidCloseSleepStatus = await batteryLidCloseSleepManager.end()
            let didRelease = batteryLidCloseSleepStatus == .inactive
            if didRelease { isBatteryLidCloseEnabled = false }
            SleepPreventionPreferences.setBatteryLidCloseEnabled(
                shouldPreservePreference ? true : !didRelease,
                defaults: defaults
            )
        }
    }
}
