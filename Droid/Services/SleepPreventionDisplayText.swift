import Foundation

enum SleepPreventionDisplayText {
    static func title(isEnabled: Bool) -> String {
        isEnabled ? "Disable Prevent Sleep" : "Enable Prevent Sleep"
    }

    static func batteryLidCloseTitle(isEnabled: Bool) -> String {
        isEnabled ? "Disable Battery Lid Sleep Override" : "Enable Battery Lid Sleep Override"
    }

    static func detail(
        isEnabled: Bool,
        systemSleepAssertionStatus: SystemSleepAssertionStatus = .inactive
    ) -> String {
        guard isEnabled else {
            return "Keep Droid running during long agent work, including lid-close sleep on AC power"
        }

        switch systemSleepAssertionStatus {
        case .active:
            return "Droid is keeping macOS awake and requesting AC-powered lid-close protection"
        case .unavailable:
            return "Idle sleep prevention is active, but /usr/bin/caffeinate is unavailable for lid-close protection"
        case .failed:
            return "Idle sleep prevention is active, but Droid could not start caffeinate for lid-close protection"
        case .inactive:
            return "Droid is keeping macOS from idle sleeping"
        }
    }

    static func batteryLidCloseDetail(
        isEnabled: Bool,
        status: SystemSleepAssertionStatus = .inactive
    ) -> String {
        guard isEnabled else {
            switch status {
            case .unavailable:
                return "pmset or osascript is unavailable for the battery lid-close override"
            case .failed:
                return "Droid could not update pmset for battery lid-close sleep"
            case .inactive,
                 .active:
                return "Advanced: uses admin permission to keep Droid running when the lid closes on battery"
            }
        }

        switch status {
        case .active:
            return "Battery lid-close sleep is disabled system-wide until Droid restores it"
        case .unavailable:
            return "pmset or osascript is unavailable for the battery lid-close override"
        case .failed:
            return "Droid could not update pmset for battery lid-close sleep"
        case .inactive:
            return "Droid will request the battery lid-close override"
        }
    }
}
