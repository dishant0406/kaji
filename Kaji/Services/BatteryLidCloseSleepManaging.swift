import Foundation

@MainActor
protocol BatteryLidCloseSleepManaging {
    var status: SystemSleepAssertionStatus { get }

    func begin() -> SystemSleepAssertionStatus
    func end() -> SystemSleepAssertionStatus
}
