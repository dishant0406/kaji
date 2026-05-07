import Foundation

@MainActor
protocol SystemSleepAssertionManaging {
    var status: SystemSleepAssertionStatus { get }

    func begin() -> SystemSleepAssertionStatus
    func end()
}
