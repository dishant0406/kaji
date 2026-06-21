import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
final class KajiAgentTimelineRowStore {
    private(set) var rows: [KajiAgentTimelineRow] = []
    private(set) var version = 0
    private var rowIndexByID: [KajiAgentTimelineRowID: Int] = [:]
    private var expandedToolGroups: Set<UUID> = []
    private var expandedTools: Set<UUID> = []
    private var expandedThinking: Set<UUID> = []

    func rebuild(turns: [KajiAgentTurn], widgetLines: [String], queuedMessageCount: Int) {
        let nextRows = KajiAgentTimelineFlattener.rows(
            turns: turns,
            widgetLines: widgetLines,
            queuedMessageCount: queuedMessageCount,
            expansion: KajiAgentTimelineExpansionState(
                toolGroups: expandedToolGroups,
                thinking: expandedThinking,
                tools: expandedTools
            )
        )
        replaceRows(nextRows)
    }

    func setLatestTurnSpacer(turnID: UUID?, height: CGFloat) {
        var nextRows = rows.filter { row in
            if case .latestTurnSpacer = row.kind { return false }
            return true
        }
        if let turnID, height > 0, let bottomIndex = nextRows.firstIndex(where: { $0.kind == .bottom }) {
            nextRows.insert(KajiAgentTimelineRow(
                id: .init(rawValue: "turn.\(turnID.uuidString).spacer"),
                turnID: turnID,
                startsTurn: false,
                isLatestTurn: true,
                kind: .latestTurnSpacer(height)
            ), at: bottomIndex)
        }
        replaceRows(nextRows)
    }

    func isToolGroupExpanded(_ id: UUID) -> Bool {
        expandedToolGroups.contains(id)
    }

    func isToolExpanded(_ id: UUID) -> Bool {
        expandedTools.contains(id)
    }

    func isThinkingExpanded(_ id: UUID) -> Bool {
        expandedThinking.contains(id)
    }

    func toggleToolGroup(_ id: UUID) {
        if expandedToolGroups.contains(id) {
            expandedToolGroups.remove(id)
            updateActivityRow(id)
            return
        }
        expandedToolGroups.insert(id)
        updateActivityRow(id)
    }

    func toggleTool(_ id: UUID) {
        if expandedTools.contains(id) {
            expandedTools.remove(id)
        } else {
            expandedTools.insert(id)
        }
        updateToolRow(id)
    }

    func toggleThinking(_ id: UUID) {
        if expandedThinking.contains(id) {
            expandedThinking.remove(id)
        } else {
            expandedThinking.insert(id)
        }
        updateThinkingRow(id)
    }

    func rowID(forTool id: UUID) -> KajiAgentTimelineRowID? {
        rows.first { row in
            if case let .tool(message, _) = row.kind { return message.id == id }
            return false
        }?.id
    }

    func rowID(forThinking id: UUID) -> KajiAgentTimelineRowID? {
        rows.first { row in
            if case let .plan(plan, _) = row.kind { return plan.id == id }
            if case let .thinking(message, _) = row.kind { return message.id == id }
            return false
        }?.id
    }

    func rowID(forToolGroup id: UUID) -> KajiAgentTimelineRowID? {
        rows.first { row in
            if case let .activity(activity, _) = row.kind { return activity.id == id }
            if case let .toolGroupHeader(group) = row.kind { return group.id == id }
            return false
        }?.id
    }

    private func updateToolRow(_ id: UUID) {
        guard let index = rows.firstIndex(where: { row in
            if case let .tool(message, _) = row.kind { return message.id == id }
            return false
        }), case let .tool(message, _) = rows[index].kind
        else { return }
        rows[index] = rows[index].copy(kind: .tool(message, expanded: expandedTools.contains(id)))
        rebuildIndex()
        version &+= 1
    }

    private func updateThinkingRow(_ id: UUID) {
        guard let index = rows.firstIndex(where: { row in
            if case let .plan(plan, _) = row.kind { return plan.id == id }
            if case let .thinking(message, _) = row.kind { return message.id == id }
            return false
        })
        else { return }
        switch rows[index].kind {
        case let .plan(plan, _):
            rows[index] = rows[index].copy(kind: .plan(plan, expanded: expandedThinking.contains(id)))
        case let .thinking(message, _):
            rows[index] = rows[index].copy(kind: .thinking(message, expanded: expandedThinking.contains(id)))
        default:
            return
        }
        rebuildIndex()
        version &+= 1
    }

    private func updateActivityRow(_ id: UUID) {
        guard let index = rows.firstIndex(where: { row in
            if case let .activity(activity, _) = row.kind { return activity.id == id }
            return false
        }), case let .activity(activity, _) = rows[index].kind
        else { return }
        rows[index] = rows[index].copy(kind: .activity(activity, expanded: expandedToolGroups.contains(id)))
        rebuildIndex()
        version &+= 1
    }

    func index(for id: KajiAgentTimelineRowID) -> Int? {
        rowIndexByID[id]
    }

    private func replaceRows(_ nextRows: [KajiAgentTimelineRow]) {
        guard rows != nextRows else { return }
        if rows.map(\.id) == nextRows.map(\.id) {
            for index in nextRows.indices where rows[index] != nextRows[index] {
                rows[index] = nextRows[index]
            }
            version &+= 1
            return
        }
        rows = nextRows
        rebuildIndex()
        version &+= 1
    }

    private func rebuildIndex() {
        rowIndexByID = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.element.id, $0.offset) })
    }
}
