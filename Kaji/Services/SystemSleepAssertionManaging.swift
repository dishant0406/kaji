import Foundation

@MainActor
protocol SystemSleepAssertionManaging {
    var status: SystemSleepAssertionStatus { get }

    func begin() -> SystemSleepAssertionStatus
    func reconcile() -> SystemSleepAssertionStatus
    func end() -> SystemSleepAssertionStatus
}
