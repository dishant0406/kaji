import Foundation

protocol SleepActivityManaging {
    func begin(reason: String) -> NSObjectProtocol
    func end(_ activity: NSObjectProtocol)
}

struct ProcessInfoSleepActivityManager: SleepActivityManaging {
    func begin(reason: String) -> NSObjectProtocol {
        ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: reason
        )
    }

    func end(_ activity: NSObjectProtocol) {
        ProcessInfo.processInfo.endActivity(activity)
    }
}
