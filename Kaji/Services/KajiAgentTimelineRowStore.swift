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
            collapseToolGroup(id)
            return
        }
        expandedToolGroups.insert(id)
        expandToolGroup(id)
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
            if case let .thinking(message, _) = row.kind { return message.id == id }
            return false
        }?.id
    }

    private func updateToolRow(_ id: UUID) {
        guard let index = rows.firstIndex(where: { row in
            if case let .tool(message, _) = row.kind { return message.id == id }
            return false
        }), case let .tool(message, _) = rows[index].kind else { return }
        rows[index] = rows[index].copy(kind: .tool(message, expanded: expandedTools.contains(id)))
        rebuildIndex()
        version &+= 1
    }

    private func updateThinkingRow(_ id: UUID) {
        guard let index = rows.firstIndex(where: { row in
            if case let .thinking(message, _) = row.kind { return message.id == id }
            return false
        }), case let .thinking(message, _) = rows[index].kind else { return }
        rows[index] = rows[index].copy(kind: .thinking(message, expanded: expandedThinking.contains(id)))
        rebuildIndex()
        version &+= 1
    }

    func index(for id: KajiAgentTimelineRowID) -> Int? {
        rowIndexByID[id]
    }

    private func expandToolGroup(_ id: UUID) {
        guard let headerIndex = rows.firstIndex(where: { row in
            if case let .toolGroupHeader(group) = row.kind { return group.id == id }
            return false
        }), case let .toolGroupHeader(group) = rows[headerIndex].kind
        else { return }
        let parentID = rows[headerIndex].id
        let childRows = group.tools.map { tool in
            KajiAgentTimelineRow(
                id: .init(rawValue: "tool.\(tool.id.uuidString)"),
                turnID: rows[headerIndex].turnID,
                startsTurn: false,
                isLatestTurn: rows[headerIndex].isLatestTurn,
                kind: .tool(tool, expanded: expandedTools.contains(tool.id)),
                depth: 1,
                parentID: parentID
            )
        }
        rows.insert(contentsOf: childRows, at: headerIndex + 1)
        rebuildIndex()
        version &+= 1
    }

    private func collapseToolGroup(_ id: UUID) {
        guard let headerIndex = rows.firstIndex(where: { row in
            if case let .toolGroupHeader(group) = row.kind { return group.id == id }
            return false
        })
        else { return }
        let parentID = rows[headerIndex].id
        rows.removeAll { $0.parentID == parentID }
        rebuildIndex()
        version &+= 1
    }

    private func replaceRows(_ nextRows: [KajiAgentTimelineRow]) {
        guard rows != nextRows else { return }
        rows = nextRows
        rebuildIndex()
        version &+= 1
    }

    private func rebuildIndex() {
        rowIndexByID = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.element.id, $0.offset) })
    }
}
