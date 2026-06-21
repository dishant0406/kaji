import Foundation

enum KajiAgentAssistantTimelineApplier {
    static func appendStart(
        content: KajiAgentJSONValue?,
        turns: inout [KajiAgentTurn],
        activeTurnID: inout KajiAgentTurn.ID?,
        tailVersion: inout Int
    ) {
        let parts = KajiAgentTextExtractor.blocks(from: content)
        guard !parts.isEmpty else { return }
        for part in parts.sorted(by: { ($0.index ?? 0) < ($1.index ?? 0) }) where !part.text.isEmpty {
            switch part.kind {
            case .text,
                 .image:
                append(
                    message: KajiAgentMessage(
                        id: KajiAgentAssistantMessageIdentity.id(
                            kind: .assistant,
                            namespace: "assistant",
                            contentIndex: part.index,
                            turns: &turns,
                            activeTurnID: &activeTurnID
                        ),
                        kind: .assistant,
                        title: "Kaji",
                        detail: part.text,
                        contentIndex: part.index,
                        isComplete: false
                    ),
                    turns: &turns,
                    activeTurnID: &activeTurnID,
                    tailVersion: &tailVersion
                )
            case .thinking:
                append(
                    message: KajiAgentMessage(
                        id: KajiAgentAssistantMessageIdentity.id(
                            kind: .thinking,
                            namespace: "thinking",
                            contentIndex: part.index,
                            turns: &turns,
                            activeTurnID: &activeTurnID
                        ),
                        kind: .thinking,
                        title: "Thinking",
                        detail: part.text,
                        contentIndex: part.index,
                        isComplete: false
                    ),
                    turns: &turns,
                    activeTurnID: &activeTurnID,
                    tailVersion: &tailVersion
                )
            }
        }
    }

    static func apply(
        update: KajiAgentAssistantMessageEvent?,
        turns: inout [KajiAgentTurn],
        activeTurnID: inout KajiAgentTurn.ID?,
        tailVersion: inout Int
    ) {
        guard let update else { return }
        switch update.type {
        case "text_delta":
            appendAssistantDelta(
                update.delta ?? "",
                contentIndex: update.contentIndex,
                turns: &turns,
                activeTurnID: &activeTurnID,
                tailVersion: &tailVersion
            )
        case "thinking_delta":
            appendThinkingDelta(
                update.delta ?? "",
                contentIndex: update.contentIndex,
                turns: &turns,
                activeTurnID: &activeTurnID,
                tailVersion: &tailVersion
            )
        default:
            break
        }
    }

    private static func appendAssistantDelta(
        _ text: String,
        contentIndex: Int?,
        turns: inout [KajiAgentTurn],
        activeTurnID: inout KajiAgentTurn.ID?,
        tailVersion: inout Int
    ) {
        guard !text.isEmpty else { return }
        KajiAgentTimeline.bumpTail(tailVersion: &tailVersion)
        KajiAgentEventLog.record("assistant_delta", fields: deltaFields(text: text, contentIndex: contentIndex, activeTurnID: activeTurnID))
        if let location = KajiAgentTimeline.responseLocation(
            turns: turns,
            activeTurnID: activeTurnID,
            where: { $0.kind == .assistant && !$0.isComplete && $0.contentIndex == contentIndex }
        ) {
            KajiAgentTimeline.updateMessage(at: location, turns: &turns) { $0.detail += text }
        } else {
            append(
                message: KajiAgentMessage(
                    id: KajiAgentAssistantMessageIdentity.id(
                        kind: .assistant,
                        namespace: "assistant",
                        contentIndex: contentIndex,
                        turns: &turns,
                        activeTurnID: &activeTurnID
                    ),
                    kind: .assistant,
                    title: "Kaji",
                    detail: text,
                    contentIndex: contentIndex,
                    isComplete: false
                ),
                turns: &turns,
                activeTurnID: &activeTurnID,
                tailVersion: &tailVersion
            )
        }
    }

    private static func appendThinkingDelta(
        _ text: String,
        contentIndex: Int?,
        turns: inout [KajiAgentTurn],
        activeTurnID: inout KajiAgentTurn.ID?,
        tailVersion: inout Int
    ) {
        guard !text.isEmpty else { return }
        KajiAgentTimeline.bumpTail(tailVersion: &tailVersion)
        KajiAgentEventLog.record("thinking_delta", fields: deltaFields(text: text, contentIndex: contentIndex, activeTurnID: activeTurnID))
        if let location = KajiAgentTimeline.activeTailMessageLocation(
            turns: turns,
            activeTurnID: activeTurnID,
            where: { $0.kind == .thinking && !$0.isComplete && $0.contentIndex == contentIndex }
        ) {
            KajiAgentTimeline.updateMessage(at: location, turns: &turns) { $0.detail += text }
        } else {
            append(
                message: KajiAgentMessage(
                    id: KajiAgentAssistantMessageIdentity.id(
                        kind: .thinking,
                        namespace: "thinking",
                        contentIndex: contentIndex,
                        turns: &turns,
                        activeTurnID: &activeTurnID
                    ),
                    kind: .thinking,
                    title: "Thinking",
                    detail: text,
                    contentIndex: contentIndex,
                    isComplete: false
                ),
                turns: &turns,
                activeTurnID: &activeTurnID,
                tailVersion: &tailVersion
            )
        }
    }
}
