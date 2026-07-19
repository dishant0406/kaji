import Foundation

@testable import Kaji

@MainActor
final class RecordingSystemSleepAssertionManager: SystemSleepAssertionManaging {
    private(set) var beginCount = 0
    private(set) var reconcileCount = 0
    private(set) var endCount = 0
    private(set) var status: SystemSleepAssertionStatus = .inactive
    var beginStatus: SystemSleepAssertionStatus
    var reconcileStatuses: [SystemSleepAssertionStatus]
    var endStatus: SystemSleepAssertionStatus

    init(
        beginStatus: SystemSleepAssertionStatus = .active,
        reconcileStatuses: [SystemSleepAssertionStatus] = [.active],
        endStatus: SystemSleepAssertionStatus = .inactive
    ) {
        self.beginStatus = beginStatus
        self.reconcileStatuses = reconcileStatuses
        self.endStatus = endStatus
    }

    func begin() -> SystemSleepAssertionStatus {
        beginCount += 1
        status = beginStatus
        return status
    }

    func reconcile() -> SystemSleepAssertionStatus {
        reconcileCount += 1
        status = reconcileStatuses.isEmpty ? status : reconcileStatuses.removeFirst()
        return status
    }

    func end() -> SystemSleepAssertionStatus {
        endCount += 1
        status = endStatus
        return status
    }
}

final class RecordingPowerAssertionDriver: PowerAssertionDriving {
    var createResults: [UInt32?]
    var activeIDs: Set<UInt32>
    var releaseResults: [Bool]
    private(set) var createReasons: [String] = []
    private(set) var releasedIDs: [UInt32] = []

    init(
        createResults: [UInt32?] = [1],
        activeIDs: Set<UInt32> = [1],
        releaseResults: [Bool] = [true]
    ) {
        self.createResults = createResults
        self.activeIDs = activeIDs
        self.releaseResults = releaseResults
    }

    func createIdleSleepPrevention(reason: String) -> UInt32? {
        createReasons.append(reason)
        return createResults.isEmpty ? nil : createResults.removeFirst()
    }

    func isActive(id: UInt32) -> Bool {
        activeIDs.contains(id)
    }

    func release(id: UInt32) -> Bool {
        releasedIDs.append(id)
        let result = releaseResults.isEmpty ? false : releaseResults.removeFirst()
        if result { activeIDs.remove(id) }
        return result
    }
}
