enum KajiAgentTimeline {
    static func bumpTail(tailVersion: inout Int) {
        tailVersion &+= 1
    }

    static func startTurn(
        user: KajiAgentMessage,
        turns: inout [KajiAgentTurn],
        activeTurnID: inout KajiAgentTurn.ID?,
        tailVersion: inout Int
    ) {
        bumpTail(tailVersion: &tailVersion)
        if let index = activeTurnIndex(turns: turns, activeTurnID: activeTurnID), turns[index].user == nil, turns[index].blocks.isEmpty {
            turns[index].user = user
            return
        }
        let turn = KajiAgentTurn(id: KajiAgentTranscriptIdentity.uuid("turn", user.id.uuidString), user: user)
        turns.append(turn)
        activeTurnID = turn.id
        KajiAgentEventLog.record("turn_start", fields: [
            "turn": .string(turn.id.uuidString),
            "userPreview": .string(String(user.detail.prefix(160))),
            "turnCount": .number(Double(turns.count)),
        ])
    }

    static func appendResponseMessage(
        _ message: KajiAgentMessage,
        turns: inout [KajiAgentTurn],
        activeTurnID: inout KajiAgentTurn.ID?,
        tailVersion: inout Int
    ) {
        bumpTail(tailVersion: &tailVersion)
        ensureActiveTurn(turns: &turns, activeTurnID: &activeTurnID)
        guard let index = activeTurnIndex(turns: turns, activeTurnID: activeTurnID) else { return }
        turns[index].blocks.append(.message(message))
    }

    static func ensureActiveTurn(turns: inout [KajiAgentTurn], activeTurnID: inout KajiAgentTurn.ID?) {
        if activeTurnIndex(turns: turns, activeTurnID: activeTurnID) != nil { return }
        let turn = KajiAgentTurn(user: nil)
        turns.append(turn)
        activeTurnID = turn.id
    }

    static func activeTurnIndex(turns: [KajiAgentTurn], activeTurnID: KajiAgentTurn.ID?) -> Int? {
        guard let activeTurnID else { return nil }
        return turns.firstIndex { $0.id == activeTurnID }
    }

    static func responseLocation(
        turns: [KajiAgentTurn],
        activeTurnID: KajiAgentTurn.ID?,
        where predicate: (KajiAgentMessage) -> Bool
    ) -> KajiAgentResponseLocation? {
        if let activeIndex = activeTurnIndex(turns: turns, activeTurnID: activeTurnID),
           let blockIndex = turns[activeIndex].blocks.lastIndex(where: { block in
               if case let .message(message) = block { return predicate(message) }
               return false
           })
        {
            return KajiAgentResponseLocation(turn: activeIndex, block: blockIndex)
        }
        for turnIndex in turns.indices.reversed() {
            if let blockIndex = turns[turnIndex].blocks.lastIndex(where: { block in
                if case let .message(message) = block { return predicate(message) }
                return false
            }) {
                return KajiAgentResponseLocation(turn: turnIndex, block: blockIndex)
            }
        }
        return nil
    }

    static func activeTailMessageLocation(
        turns: [KajiAgentTurn],
        activeTurnID: KajiAgentTurn.ID?,
        where predicate: (KajiAgentMessage) -> Bool
    ) -> KajiAgentResponseLocation? {
        guard let turnIndex = activeTurnIndex(turns: turns, activeTurnID: activeTurnID),
              let last = turns[turnIndex].blocks.indices.last,
              case let .message(message) = turns[turnIndex].blocks[last], predicate(message)
        else { return nil }
        return KajiAgentResponseLocation(turn: turnIndex, block: last)
    }

    static func updateMessage(
        at location: KajiAgentResponseLocation,
        turns: inout [KajiAgentTurn],
        mutate: (inout KajiAgentMessage) -> Void
    ) {
        guard case var .message(message) = turns[location.turn].blocks[location.block] else { return }
        mutate(&message)
        turns[location.turn].blocks[location.block] = .message(message)
    }
}
