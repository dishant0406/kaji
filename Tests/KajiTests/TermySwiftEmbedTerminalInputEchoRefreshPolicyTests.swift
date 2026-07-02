import XCTest
@testable import TermySwiftEmbed

final class TerminalInputEchoRefreshPolicyTests: XCTestCase {
    func testActiveWakeupIsIgnoredWithoutPendingInput() {
        let policy = TerminalInputEchoRefreshPolicy()

        XCTAssertFalse(policy.acceptsWakeup(cadence: .active))
        XCTAssertNil(policy.activeInputGenerationForWakeup(cadence: .active))
    }

    func testActiveWakeupIsAcceptedAfterInputUntilPollCompletes() {
        var policy = TerminalInputEchoRefreshPolicy()
        let generation = policy.noteInput()

        XCTAssertTrue(policy.acceptsWakeup(cadence: .active))
        XCTAssertEqual(policy.activeInputGenerationForWakeup(cadence: .active), generation)

        policy.recordPoll(upTo: generation, observedFrameActivity: true)

        XCTAssertFalse(policy.acceptsWakeup(cadence: .active))
        XCTAssertNil(policy.activeInputGenerationForWakeup(cadence: .active))
    }

    func testOldPollDoesNotClearNewerPendingInput() {
        var policy = TerminalInputEchoRefreshPolicy()
        let firstGeneration = policy.noteInput()
        let secondGeneration = policy.noteInput()

        policy.recordPoll(upTo: firstGeneration, observedFrameActivity: false)

        XCTAssertTrue(policy.hasPendingInput)
        XCTAssertEqual(policy.pendingInputGenerationForRefresh, secondGeneration)
        XCTAssertEqual(policy.activeInputGenerationForWakeup(cadence: .active), secondGeneration)

        policy.recordPoll(upTo: secondGeneration, observedFrameActivity: true)

        XCTAssertFalse(policy.hasPendingInput)
    }

    func testEmptyPollKeepsInputPendingBeforeRetryLimit() {
        var policy = TerminalInputEchoRefreshPolicy()
        policy.maxEmptyPollCount = 2
        let generation = policy.noteInput()

        XCTAssertFalse(policy.recordPoll(upTo: generation, observedFrameActivity: false))

        XCTAssertTrue(policy.hasPendingInput)
        XCTAssertEqual(policy.emptyPollCount, 1)
        XCTAssertTrue(policy.acceptsWakeup(cadence: .active))
    }

    func testEmptyPollExpiresInputAtRetryLimit() {
        var policy = TerminalInputEchoRefreshPolicy()
        policy.maxEmptyPollCount = 2
        let generation = policy.noteInput()

        policy.recordPoll(upTo: generation, observedFrameActivity: false)
        XCTAssertTrue(policy.recordPoll(upTo: generation, observedFrameActivity: false))

        XCTAssertFalse(policy.hasPendingInput)
        XCTAssertEqual(policy.emptyPollCount, 0)
        XCTAssertFalse(policy.acceptsWakeup(cadence: .active))
    }

    func testIdleWakeupsAreAcceptedWithoutPendingInput() {
        let policy = TerminalInputEchoRefreshPolicy()

        XCTAssertTrue(policy.acceptsWakeup(cadence: .idle))
        XCTAssertTrue(policy.acceptsWakeup(cadence: .idleInert))
    }

    func testSuspendedWakeupsAreAcceptedWithoutPendingInput() {
        let policy = TerminalInputEchoRefreshPolicy()

        XCTAssertTrue(policy.acceptsWakeup(cadence: .active, isSuspended: true))
        XCTAssertTrue(policy.acceptsWakeup(cadence: .idle, isSuspended: true))
        XCTAssertTrue(policy.acceptsWakeup(cadence: .idleInert, isSuspended: true))
    }

    func testVisibleActiveWakeupsStillRequirePendingInput() {
        var policy = TerminalInputEchoRefreshPolicy()

        XCTAssertFalse(policy.acceptsWakeup(cadence: .active, isSuspended: false))

        _ = policy.noteInput()

        XCTAssertTrue(policy.acceptsWakeup(cadence: .active, isSuspended: false))
    }

    func testResetClearsPendingInput() {
        var policy = TerminalInputEchoRefreshPolicy()
        _ = policy.noteInput()

        policy.reset()

        XCTAssertFalse(policy.hasPendingInput)
        XCTAssertNil(policy.pendingInputGenerationForRefresh)
    }
}
