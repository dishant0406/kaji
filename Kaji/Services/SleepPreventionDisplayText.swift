import Foundation

enum SleepPreventionDisplayText {
    static func title(isEnabled: Bool) -> String {
        isEnabled ? "Disable Idle Sleep Prevention" : "Enable Idle Sleep Prevention"
    }

    static func detail(
        isEnabled: Bool,
        systemSleepAssertionStatus: SystemSleepAssertionStatus = .inactive
    ) -> String {
        guard isEnabled else {
            return "Prevent automatic system sleep while Kaji is running long-lived work. Lid-close and explicit sleep are not prevented."
        }

        switch systemSleepAssertionStatus {
        case .active:
            return "Verified active: Kaji is preventing automatic idle system sleep. Lid-close and explicit sleep are not prevented."
        case .unavailable:
            return "Idle sleep prevention is unavailable on this system."
        case .failed:
            return "Kaji could not verify the idle sleep assertion."
        case .inactive:
            return "Idle sleep prevention is enabled but the assertion is not active."
        }
    }
}
