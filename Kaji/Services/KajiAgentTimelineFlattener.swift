import CoreGraphics
import Foundation

enum KajiAgentTimelineFlattener {
    static func rows(
        turns: [KajiAgentTurn],
        widgetLines: [String],
        queuedMessageCount: Int,
        expansion: KajiAgentTimelineExpansionState = .empty,
        latestTurnSpacerHeight: CGFloat = 0
    ) -> [KajiAgentTimelineRow] {
        var rows: [KajiAgentTimelineRow] = []
        if !widgetLines.isEmpty {
            rows.append(KajiAgentTimelineRow(
                id: .init(rawValue: "widget"),
                turnID: nil,
                startsTurn: false,
                isLatestTurn: false,
                kind: .widget(widgetLines),
                depth: 0,
                parentID: nil
            ))
        }
        if queuedMessageCount > 0 {
            rows.append(KajiAgentTimelineRow(
                id: .init(rawValue: "queued"),
                turnID: nil,
                startsTurn: false,
                isLatestTurn: false,
                kind: .queuedMessages(queuedMessageCount),
                depth: 0,
                parentID: nil
            ))
        }

        let latestTurnID = turns.last?.id
        for turn in turns {
            append(
                turn: turn,
                latestTurnID: latestTurnID,
                expansion: expansion,
                rows: &rows
            )
        }

        if let latestTurnID, latestTurnSpacerHeight > 0 {
            rows.append(KajiAgentTimelineRow(
                id: .init(rawValue: "turn.\(latestTurnID.uuidString).spacer"),
                turnID: latestTurnID,
                startsTurn: false,
                isLatestTurn: true,
                kind: .latestTurnSpacer(latestTurnSpacerHeight),
                depth: 0,
                parentID: nil
            ))
        }
        rows.append(KajiAgentTimelineRow(
            id: .init(rawValue: "bottom"),
            turnID: nil,
            startsTurn: false,
            isLatestTurn: false,
            kind: .bottom,
            depth: 0,
            parentID: nil
        ))
        return rows
    }

    private static func append(
        turn: KajiAgentTurn,
        latestTurnID: UUID?,
        expansion: KajiAgentTimelineExpansionState,
        rows: inout [KajiAgentTimelineRow]
    ) {
        let isLatestTurn = turn.id == latestTurnID
        var startsTurn = true
        if let user = turn.user {
            rows.append(row(
                id: "turn.\(turn.id.uuidString).user",
                turnID: turn.id,
                startsTurn: startsTurn,
                isLatestTurn: isLatestTurn,
                kind: .user(user)
            ))
            startsTurn = false
        }
        for block in turn.blocks {
            switch block {
            case let .message(message):
                let kind: KajiAgentTimelineRow.Kind = if message.kind == .thinking {
                    .thinking(message, expanded: expansion.thinking.contains(message.id))
                } else {
                    .message(message)
                }
                rows.append(row(
                    id: "message.\(message.id.uuidString)",
                    turnID: turn.id,
                    startsTurn: startsTurn,
                    isLatestTurn: isLatestTurn,
                    kind: kind
                ))
                startsTurn = false
            case let .toolGroup(group):
                let groupRowID = KajiAgentTimelineRowID(rawValue: "toolGroup.\(group.id.uuidString)")
                rows.append(row(
                    id: groupRowID.rawValue,
                    turnID: turn.id,
                    startsTurn: startsTurn,
                    isLatestTurn: isLatestTurn,
                    kind: .toolGroupHeader(group)
                ))
                startsTurn = false
                if expansion.toolGroups.contains(group.id) {
                    rows.append(contentsOf: group.tools.map { tool in
                        row(
                            id: "tool.\(tool.id.uuidString)",
                            turnID: turn.id,
                            startsTurn: false,
                            isLatestTurn: isLatestTurn,
                            kind: .tool(tool, expanded: expansion.tools.contains(tool.id)),
                            depth: 1,
                            parentID: groupRowID
                        )
                    })
                }
            }
        }
    }

    private static func row(
        id: String,
        turnID: UUID,
        startsTurn: Bool,
        isLatestTurn: Bool,
        kind: KajiAgentTimelineRow.Kind,
        depth: Int = 0,
        parentID: KajiAgentTimelineRowID? = nil
    ) -> KajiAgentTimelineRow {
        KajiAgentTimelineRow(
            id: .init(rawValue: id),
            turnID: turnID,
            startsTurn: startsTurn,
            isLatestTurn: isLatestTurn,
            kind: kind,
            depth: depth,
            parentID: parentID
        )
    }
}
