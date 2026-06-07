import CoreGraphics

struct KajiAgentScrollLockState: Equatable {
    var isLocked: Bool
    var hasUnseenTail: Bool
}

struct KajiAgentScrollLockPolicy {
    static let pinnedThreshold: CGFloat = 4
    static let awayThreshold: CGFloat = 8

    static func observedState(distanceFromBottom: CGFloat, current: KajiAgentScrollLockState) -> KajiAgentScrollLockState {
        if distanceFromBottom <= pinnedThreshold {
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
        !current.isLocked && distanceFromBottom <= pinnedThreshold
    }

    static func tailChangedState(distanceFromBottom: CGFloat, current: KajiAgentScrollLockState) -> KajiAgentScrollLockState? {
        guard !current.isLocked, distanceFromBottom <= pinnedThreshold else {
            return KajiAgentScrollLockState(isLocked: true, hasUnseenTail: true)
        }
        return nil
    }
}
