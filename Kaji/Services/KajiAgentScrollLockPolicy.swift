import CoreGraphics

struct KajiAgentScrollLockState: Equatable {
    var isLocked: Bool
    var hasUnseenTail: Bool
}

enum KajiAgentScrollLockPolicy {
    static let pinnedThreshold: CGFloat = 4
    static let awayThreshold: CGFloat = 16
    static let resumeThreshold: CGFloat = 56

    static func observedState(
        distanceFromBottom: CGFloat,
        isScrollingDown: Bool = false,
        current: KajiAgentScrollLockState
    ) -> KajiAgentScrollLockState {
        if distanceFromBottom <= pinnedThreshold {
            return KajiAgentScrollLockState(isLocked: false, hasUnseenTail: false)
        }
        if current.isLocked, isScrollingDown, distanceFromBottom <= resumeThreshold {
            return KajiAgentScrollLockState(isLocked: false, hasUnseenTail: false)
        }
        if distanceFromBottom >= awayThreshold {
            return KajiAgentScrollLockState(isLocked: true, hasUnseenTail: current.hasUnseenTail)
        }
        return current
    }

    static func manualScrollState(current: KajiAgentScrollLockState) -> KajiAgentScrollLockState {
        KajiAgentScrollLockState(isLocked: true, hasUnseenTail: current.hasUnseenTail)
    }

    static func shouldPerformAutoScroll(distanceFromBottom: CGFloat, current: KajiAgentScrollLockState) -> Bool {
        !current.isLocked && distanceFromBottom <= resumeThreshold
    }

    static func tailChangedState(distanceFromBottom: CGFloat, current: KajiAgentScrollLockState) -> KajiAgentScrollLockState? {
        guard !current.isLocked, distanceFromBottom <= resumeThreshold else {
            return KajiAgentScrollLockState(isLocked: true, hasUnseenTail: true)
        }
        return nil
    }
}
