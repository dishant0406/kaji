import CoreGraphics
import Foundation

struct KajiAgentTimelineRowID: Hashable, CustomStringConvertible {
    let rawValue: String

    var description: String { rawValue }
}

extension KajiAgentTimelineRow {
    var isSpacer: Bool {
        if case .latestTurnSpacer = kind { return true }
        return false
    }
}

struct KajiAgentTimelineRow: Identifiable, Hashable {
    enum Kind: Hashable {
        case widget([String])
        case queuedMessages(Int)
        case user(KajiAgentMessage)
        case message(KajiAgentMessage)
        case toolGroupHeader(KajiAgentToolGroup)
        case tool(KajiAgentMessage)
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
