import CoreGraphics
import Foundation

struct KajiAgentTimelineRowID: Hashable, CustomStringConvertible {
    let rawValue: String

    var description: String { rawValue }
}

extension KajiAgentTimelineRow {
    func copy(kind nextKind: Kind) -> KajiAgentTimelineRow {
        KajiAgentTimelineRow(
            id: id,
            turnID: turnID,
            startsTurn: startsTurn,
            isLatestTurn: isLatestTurn,
            kind: nextKind,
            depth: depth,
            parentID: parentID
        )
    }
}

extension KajiAgentTimelineRow {
    var isSpacer: Bool {
        if case .latestTurnSpacer = kind {
            return true
        }
        return false
    }
}

struct KajiAgentTimelineRow: Identifiable, Hashable {
    enum Kind: Hashable {
        case widget([String])
        case queuedMessages(Int)
        case user(KajiAgentMessage)
        case message(KajiAgentMessage)
        case plan(KajiAgentPlanSummary, expanded: Bool)
        case activity(KajiAgentActivitySummary, expanded: Bool)
        case thinking(KajiAgentMessage, expanded: Bool)
        case toolGroupHeader(KajiAgentToolGroup)
        case tool(KajiAgentMessage, expanded: Bool)
        case latestTurnSpacer(CGFloat)
        case bottom
    }

    let id: KajiAgentTimelineRowID
    let turnID: UUID?
    let startsTurn: Bool
    let isLatestTurn: Bool
    let kind: Kind
    let depth: Int
    let parentID: KajiAgentTimelineRowID?

    init(
        id: KajiAgentTimelineRowID,
        turnID: UUID?,
        startsTurn: Bool,
        isLatestTurn: Bool,
        kind: Kind,
        depth: Int = 0,
        parentID: KajiAgentTimelineRowID? = nil
    ) {
        self.id = id
        self.turnID = turnID
        self.startsTurn = startsTurn
        self.isLatestTurn = isLatestTurn
        self.kind = kind
        self.depth = depth
        self.parentID = parentID
    }
}

extension KajiAgentTimelineRow {
    func preservesMeasuredHeight(replacing old: KajiAgentTimelineRow) -> Bool {
        guard id == old.id else { return false }
        switch (old.kind, kind) {
        case let (.message(oldMessage), .message(newMessage)):
            return oldMessage.preservesMeasuredHeight(replacing: newMessage)
        case let (.plan(oldPlan, oldExpanded), .plan(newPlan, newExpanded)):
            return oldExpanded == newExpanded && oldPlan.id == newPlan.id
        default:
            return self == old
        }
    }
}

private extension KajiAgentMessage {
    func preservesMeasuredHeight(replacing next: KajiAgentMessage) -> Bool {
        id == next.id
            && kind == next.kind
            && kind == .assistant
            && !isComplete
            && !next.isComplete
    }
}
