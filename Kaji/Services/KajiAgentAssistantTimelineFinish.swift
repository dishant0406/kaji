extension KajiAgentAssistantTimelineApplier {
    static func finishOpenThinkingBlocks(from value: KajiAgentJSONValue?, turns: inout [KajiAgentTurn], activeTurnID: KajiAgentTurn.ID?) {
        let thinking = KajiAgentTextExtractor.blocks(from: value).filter { $0.kind == .thinking }
        for part in thinking {
            guard let location = KajiAgentTimeline.responseLocation(
                turns: turns,
                activeTurnID: activeTurnID,
                where: { $0.kind == .thinking && $0.contentIndex == part.index }
            )
            else { continue }
            KajiAgentTimeline.updateMessage(at: location, turns: &turns) { message in
                if !part.text.isEmpty { message.detail = part.text }
                message.isComplete = true
            }
        }
        guard let turnIndex = KajiAgentTimeline.activeTurnIndex(turns: turns, activeTurnID: activeTurnID) else { return }
        for blockIndex in turns[turnIndex].blocks.indices {
            guard case var .message(message) = turns[turnIndex].blocks[blockIndex], message.kind == .thinking,
                  !message.isComplete
            else { continue }
            message.isComplete = true
            turns[turnIndex].blocks[blockIndex] = .message(message)
        }
    }

    static func append(
        message: KajiAgentMessage,
        turns: inout [KajiAgentTurn],
        activeTurnID: inout KajiAgentTurn.ID?,
        tailVersion: inout Int
    ) {
        KajiAgentTimeline.appendResponseMessage(
            message,
            turns: &turns,
            activeTurnID: &activeTurnID,
            tailVersion: &tailVersion
        )
    }

    static func deltaFields(text: String, contentIndex: Int?, activeTurnID: KajiAgentTurn.ID?) -> [String: KajiAgentJSONValue] {
        [
            "contentIndex": contentIndex.map { .number(Double($0)) } ?? .null,
            "characters": .number(Double(text.count)),
            "turn": .string(activeTurnID?.uuidString ?? ""),
        ]
    }
}
