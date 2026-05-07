import Foundation

enum SleepPreventionPreferences {
    static let isEnabledKey = "droid.power.preventIdleSystemSleep"
    static let batteryLidCloseIsEnabledKey = "droid.power.preventBatteryLidCloseSleep"

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: isEnabledKey)
    }

    static func setEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: isEnabledKey)
    }

    static func batteryLidCloseIsEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: batteryLidCloseIsEnabledKey)
    }

    static func setBatteryLidCloseEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: batteryLidCloseIsEnabledKey)
    }
}
