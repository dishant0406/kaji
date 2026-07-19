import Foundation

enum SleepPreventionPreferences {
    static let isEnabledKey = "kaji.power.preventIdleSystemSleep"

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: isEnabledKey)
    }

    static func setEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: isEnabledKey)
    }
}
