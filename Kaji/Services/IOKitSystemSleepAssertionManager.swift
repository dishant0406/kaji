import Foundation
import IOKit.pwr_mgt

protocol PowerAssertionDriving {
    func createIdleSleepPrevention(reason: String) -> UInt32?
    func isActive(id: UInt32) -> Bool
    func release(id: UInt32) -> Bool
}

struct IOKitPowerAssertionDriver: PowerAssertionDriving {
    func createIdleSleepPrevention(reason: String) -> UInt32? {
        var assertionID = IOPMAssertionID(kIOPMNullAssertionID)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )
        return result == kIOReturnSuccess ? assertionID : nil
    }

    func isActive(id: UInt32) -> Bool {
        guard let properties = IOPMAssertionCopyProperties(id)?.takeRetainedValue() as? [String: Any],
              properties[kIOPMAssertionTypeKey] as? String == kIOPMAssertPreventUserIdleSystemSleep,
              let level = properties[kIOPMAssertionLevelKey] as? NSNumber
        else { return false }
        return level.uint32Value == IOPMAssertionLevel(kIOPMAssertionLevelOn)
    }

    func release(id: UInt32) -> Bool {
        IOPMAssertionRelease(id) == kIOReturnSuccess
    }
}

@MainActor
final class IOKitSystemSleepAssertionManager: SystemSleepAssertionManaging {
    private let driver: PowerAssertionDriving
    private let reason: String
    private var assertionID: UInt32?
    private(set) var status: SystemSleepAssertionStatus = .inactive

    init(
        driver: PowerAssertionDriving = IOKitPowerAssertionDriver(),
        reason: String = "Kaji long-lived terminal and agent sessions"
    ) {
        self.driver = driver
        self.reason = reason
    }

    func begin() -> SystemSleepAssertionStatus {
        if let assertionID, driver.isActive(id: assertionID) {
            status = .active
            return status
        }
        releaseInvalidAssertion()
        guard let newAssertionID = driver.createIdleSleepPrevention(reason: reason) else {
            status = .failed
            return status
        }
        guard driver.isActive(id: newAssertionID) else {
            _ = driver.release(id: newAssertionID)
            status = .failed
            return status
        }
        assertionID = newAssertionID
        status = .active
        return status
    }

    func reconcile() -> SystemSleepAssertionStatus {
        begin()
    }

    func end() -> SystemSleepAssertionStatus {
        guard let assertionID else {
            status = .inactive
            return status
        }
        if driver.release(id: assertionID) || !driver.isActive(id: assertionID) {
            self.assertionID = nil
            status = .inactive
            return status
        }
        status = .failed
        return status
    }

    private func releaseInvalidAssertion() {
        guard let assertionID else { return }
        _ = driver.release(id: assertionID)
        self.assertionID = nil
    }
}
