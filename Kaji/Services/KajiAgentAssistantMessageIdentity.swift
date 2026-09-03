import Foundation

enum KajiAgentAssistantMessageIdentity {
    static func id(
        kind: KajiAgentMessageKind,
        namespace: String,
        contentIndex: Int?,
        turns: inout [KajiAgentTurn],
        activeTurnID: inout KajiAgentTurn.ID?
    ) -> UUID {
        KajiAgentTimeline.ensureActiveTurn(turns: &turns, activeTurnID: &activeTurnID)
        let turnID = activeTurnID?.uuidString ?? "no-turn"
        let ordinal = activeTurnMessages(turns: turns, activeTurnID: activeTurnID)
            .count(where: { $0.kind == kind && $0.contentIndex == contentIndex })

        return KajiAgentTranscriptIdentity.uuid(namespace, turnID, String(contentIndex ?? -1), String(ordinal))
    }

    private static func activeTurnMessages(turns: [KajiAgentTurn], activeTurnID: KajiAgentTurn.ID?) -> [KajiAgentMessage] {
        guard let turnIndex = KajiAgentTimeline.activeTurnIndex(turns: turns, activeTurnID: activeTurnID) else { return [] }
        return turns[turnIndex].blocks.compactMap { block in
            if case let .message(message) = block {
                return message
            }
            return nil
        }
    }
}
