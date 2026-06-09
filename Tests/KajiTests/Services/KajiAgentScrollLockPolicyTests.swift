import Testing

@testable import Kaji

struct KajiAgentScrollLockPolicyTests {
    @Test
    func keepsUnlockedWhenPinnedToBottom() {
        let state = KajiAgentScrollLockPolicy.observedState(
            distanceFromBottom: 0,
            current: KajiAgentScrollLockState(isLocked: false, hasUnseenTail: true)
        )

        #expect(state == KajiAgentScrollLockState(isLocked: false, hasUnseenTail: false))
    }

    @Test
    func locksOnSmallIntentionalScrollAway() {
        let state = KajiAgentScrollLockPolicy.observedState(
            distanceFromBottom: 20,
            current: KajiAgentScrollLockState(isLocked: false, hasUnseenTail: false)
        )

        #expect(state == KajiAgentScrollLockState(isLocked: true, hasUnseenTail: false))
    }

    @Test
    func staysLockedUntilPinnedAgain() {
        let state = KajiAgentScrollLockPolicy.observedState(
            distanceFromBottom: 6,
            current: KajiAgentScrollLockState(isLocked: true, hasUnseenTail: true)
        )

        #expect(state == KajiAgentScrollLockState(isLocked: true, hasUnseenTail: true))
    }

    @Test
    func manualScrollImmediatelyLocksWithoutChangingUnseenState() {
        let state = KajiAgentScrollLockPolicy.manualScrollState(
            current: KajiAgentScrollLockState(isLocked: false, hasUnseenTail: true)
        )

        #expect(state == KajiAgentScrollLockState(isLocked: true, hasUnseenTail: true))
    }

    @Test
    func autoScrollRequiresPinnedUnlockedState() {
        #expect(KajiAgentScrollLockPolicy.shouldPerformAutoScroll(
            distanceFromBottom: 0,
            current: KajiAgentScrollLockState(isLocked: false, hasUnseenTail: false)
        ))
        #expect(KajiAgentScrollLockPolicy.shouldPerformAutoScroll(
            distanceFromBottom: 40,
            current: KajiAgentScrollLockState(isLocked: false, hasUnseenTail: false)
        ))
        #expect(!KajiAgentScrollLockPolicy.shouldPerformAutoScroll(
            distanceFromBottom: 0,
            current: KajiAgentScrollLockState(isLocked: true, hasUnseenTail: false)
        ))
    }

    @Test
    func tailChangeMarksUnseenWhenAwayFromBottom() {
        let state = KajiAgentScrollLockPolicy.tailChangedState(
            distanceFromBottom: 80,
            current: KajiAgentScrollLockState(isLocked: false, hasUnseenTail: false)
        )

        #expect(state == KajiAgentScrollLockState(isLocked: true, hasUnseenTail: true))
    }

    @Test
    func tailChangeAllowsAutoscrollOnlyWhenPinned() {
        let state = KajiAgentScrollLockPolicy.tailChangedState(
            distanceFromBottom: 40,
            current: KajiAgentScrollLockState(isLocked: false, hasUnseenTail: false)
        )

        #expect(state == nil)
    }

    @Test
    func scrollingDownNearBottomUnlocksAndClearsUnseenTail() {
        let state = KajiAgentScrollLockPolicy.observedState(
            distanceFromBottom: 32,
            isScrollingDown: true,
            current: KajiAgentScrollLockState(isLocked: true, hasUnseenTail: true)
        )

        #expect(state == KajiAgentScrollLockState(isLocked: false, hasUnseenTail: false))
    }

    @Test
    func scrollingDownFarFromBottomStaysLocked() {
        let state = KajiAgentScrollLockPolicy.observedState(
            distanceFromBottom: 120,
            isScrollingDown: true,
            current: KajiAgentScrollLockState(isLocked: true, hasUnseenTail: true)
        )

        #expect(state == KajiAgentScrollLockState(isLocked: true, hasUnseenTail: true))
    }
}
