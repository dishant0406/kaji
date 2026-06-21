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

    static func finishAssistant(
        content: KajiAgentJSONValue?,
        errorMessage: String?,
        turns: inout [KajiAgentTurn],
        activeTurnID: inout KajiAgentTurn.ID?,
        tailVersion: inout Int
    ) {
        if let errorMessage, !errorMessage.isEmpty {
            KajiAgentTimeline.appendResponseMessage(
                KajiAgentMessage(
                    id: KajiAgentAssistantMessageIdentity.id(
                        kind: .error,
                        namespace: "error",
                        contentIndex: nil,
                        turns: &turns,
                        activeTurnID: &activeTurnID
                    ),
                    kind: .error,
                    title: "Provider error",
                    detail: errorMessage
                ),
                turns: &turns,
                activeTurnID: &activeTurnID,
                tailVersion: &tailVersion
            )
            return
        }
        let text = KajiAgentTextExtractor.assistantText(from: content)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            finishOpenThinkingBlocks(from: content, turns: &turns, activeTurnID: activeTurnID)
            return
        }
        if let location = KajiAgentTimeline.responseLocation(
            turns: turns,
            activeTurnID: activeTurnID,
            where: { $0.kind == .assistant && !$0.isComplete }
        ) {
            KajiAgentTimeline.updateMessage(at: location, turns: &turns) { message in
                message.detail = text
                message.isComplete = true
            }
        } else {
            KajiAgentTimeline.appendResponseMessage(
                KajiAgentMessage(
                    id: KajiAgentAssistantMessageIdentity.id(
                        kind: .assistant,
                        namespace: "assistant-final",
                        contentIndex: nil,
                        turns: &turns,
                        activeTurnID: &activeTurnID
                    ),
                    kind: .assistant,
                    title: "Kaji",
                    detail: text
                ),
                turns: &turns,
                activeTurnID: &activeTurnID,
                tailVersion: &tailVersion
            )
        }
        finishOpenThinkingBlocks(from: content, turns: &turns, activeTurnID: activeTurnID)
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
