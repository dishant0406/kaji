import Testing

@testable import Kaji

@MainActor
struct IOKitSystemSleepAssertionManagerTests {
    @Test
    func beginReturnsActiveOnlyAfterDriverVerifiesCreatedAssertion() {
        let driver = RecordingPowerAssertionDriver(createResults: [42], activeIDs: [42])
        let manager = IOKitSystemSleepAssertionManager(driver: driver, reason: "test reason")

        let status = manager.begin()

        #expect(status == .active)
        #expect(manager.status == .active)
        #expect(driver.createReasons == ["test reason"])
    }

    @Test
    func creationFailureReturnsFailedWithoutRetainingAssertion() {
        let driver = RecordingPowerAssertionDriver(createResults: [nil], activeIDs: [])
        let manager = IOKitSystemSleepAssertionManager(driver: driver)

        #expect(manager.begin() == .failed)
        #expect(manager.end() == .inactive)
        #expect(driver.releasedIDs.isEmpty)
    }

    @Test
    func failedVerificationReleasesUnverifiedAssertion() {
        let driver = RecordingPowerAssertionDriver(createResults: [7], activeIDs: [], releaseResults: [true])
        let manager = IOKitSystemSleepAssertionManager(driver: driver)

        #expect(manager.begin() == .failed)
        #expect(driver.releasedIDs == [7])
        #expect(manager.status == .failed)
    }

    @Test
    func endReleasesRetainedAssertionAndReturnsVerifiedInactiveState() {
        let driver = RecordingPowerAssertionDriver(createResults: [9], activeIDs: [9], releaseResults: [true])
        let manager = IOKitSystemSleepAssertionManager(driver: driver)
        #expect(manager.begin() == .active)

        let status = manager.end()

        #expect(status == .inactive)
        #expect(driver.releasedIDs == [9])
        #expect(!driver.activeIDs.contains(9))
    }

    @Test
    func reconcileReplacesAssertionThatIsNoLongerActiveAfterWake() {
        let driver = RecordingPowerAssertionDriver(
            createResults: [10, 11],
            activeIDs: [10],
            releaseResults: [false, true]
        )
        let manager = IOKitSystemSleepAssertionManager(driver: driver)
        #expect(manager.begin() == .active)
        driver.activeIDs.remove(10)
        driver.activeIDs.insert(11)

        let status = manager.reconcile()

        #expect(status == .active)
        #expect(driver.createReasons.count == 2)
        #expect(driver.releasedIDs == [10])
        #expect(manager.end() == .inactive)
        #expect(driver.releasedIDs == [10, 11])
    }

    @Test
    func releaseFailureReportsFailedWhileAssertionRemainsVerifiedActive() {
        let driver = RecordingPowerAssertionDriver(createResults: [12], activeIDs: [12], releaseResults: [false])
        let manager = IOKitSystemSleepAssertionManager(driver: driver)
        #expect(manager.begin() == .active)

        #expect(manager.end() == .failed)
        #expect(manager.status == .failed)
        #expect(driver.activeIDs.contains(12))
    }
    @Test
    func liveDriverCreatesVerifiesAndReleasesAssertion() throws {
        let driver = IOKitPowerAssertionDriver()
        let assertionID = try #require(driver.createIdleSleepPrevention(reason: "Kaji test assertion"))
        defer { _ = driver.release(id: assertionID) }

        #expect(driver.isActive(id: assertionID))
        #expect(driver.release(id: assertionID))
        #expect(!driver.isActive(id: assertionID))
    }
}
