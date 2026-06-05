import Foundation

@MainActor
protocol BatteryLidCloseSleepManaging {
    var status: SystemSleepAssertionStatus { get }

    func begin() async -> SystemSleepAssertionStatus
    func end() async -> SystemSleepAssertionStatus
}
