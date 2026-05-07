import Foundation

@testable import Droid

final class RecordingSleepActivityManager: SleepActivityManaging {
    private(set) var beginReasons: [String] = []
    private(set) var endedActivities: [String] = []

    func begin(reason: String) -> NSObjectProtocol {
        beginReasons.append(reason)
        return NSString(string: "activity-\(beginReasons.count)")
    }

    func end(_ activity: NSObjectProtocol) {
        endedActivities.append(activity as? String ?? "unknown")
    }
}

@MainActor
final class RecordingSystemSleepAssertionManager: SystemSleepAssertionManaging {
    private(set) var beginCount = 0
    private(set) var endCount = 0
    private(set) var status: SystemSleepAssertionStatus = .inactive
    private let beginStatus: SystemSleepAssertionStatus

    init(beginStatus: SystemSleepAssertionStatus = .active) {
        self.beginStatus = beginStatus
    }

    func begin() -> SystemSleepAssertionStatus {
        beginCount += 1
        status = beginStatus
        return status
    }

    func end() {
        endCount += 1
        status = .inactive
    }
}

@MainActor
final class RecordingBatteryLidCloseSleepManager: BatteryLidCloseSleepManaging {
    private(set) var beginCount = 0
    private(set) var endCount = 0
    private(set) var status: SystemSleepAssertionStatus = .inactive
    private let beginStatus: SystemSleepAssertionStatus

    init(beginStatus: SystemSleepAssertionStatus = .active) {
        self.beginStatus = beginStatus
    }

    func begin() -> SystemSleepAssertionStatus {
        beginCount += 1
        status = beginStatus
        return status
    }

    func end() -> SystemSleepAssertionStatus {
        endCount += 1
        status = .inactive
        return status
    }
}
