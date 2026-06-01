import Foundation

@MainActor
@Observable
final class KajiAgentTimelineScrollState {
    var isLocked = false
    var hasUnseenTail = false
    private var lastProgrammaticScrollAt = Date.distantPast

    func markProgrammaticScroll() {
        lastProgrammaticScrollAt = Date()
        isLocked = false
        hasUnseenTail = false
    }

    func observe(distanceFromBottom: CGFloat) {
        if Date().timeIntervalSince(lastProgrammaticScrollAt) < 0.35 { return }
        if distanceFromBottom < 72 {
            isLocked = false
            hasUnseenTail = false
        } else {
            isLocked = true
        }
    }

    func markTailChanged() {
        if isLocked { hasUnseenTail = true }
    }
}

enum KajiAgentTimelineScrollRequest: Equatable {
    case none
    case bottom(Int)
    case turn(UUID, Int)
}
