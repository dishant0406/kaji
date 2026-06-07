import Foundation

@MainActor
struct KajiAgentTimelineUpdateCoalescer {
    private var assistantDeltas: [AssistantDelta] = []
    private var toolUpdates: [ToolUpdate] = []

    var hasPendingAssistantDeltas: Bool { !assistantDeltas.isEmpty }
    var hasPendingToolUpdates: Bool { !toolUpdates.isEmpty }
    var hasPendingUpdates: Bool { hasPendingAssistantDeltas || hasPendingToolUpdates }

    mutating func enqueueAssistantDelta(_ update: KajiAgentAssistantMessageEvent) -> Bool {
        guard let delta = update.delta, !delta.isEmpty, update.isTimelineTextDelta else { return false }
        let key = AssistantDeltaKey(type: update.type, contentIndex: update.contentIndex)
        if let index = assistantDeltas.indices.last, assistantDeltas[index].key == key {
            assistantDeltas[index].delta += delta
            return true
        }
        assistantDeltas.append(AssistantDelta(key: key, delta: delta))
        return true
    }

    mutating func drainAssistantDeltas() -> [KajiAgentAssistantMessageEvent] {
        let updates = assistantDeltas.map { delta in
            KajiAgentAssistantMessageEvent(type: delta.key.type, delta: delta.delta, contentIndex: delta.key.contentIndex)
        }
        assistantDeltas.removeAll(keepingCapacity: true)
        return updates
    }

    mutating func enqueueToolUpdate(_ event: KajiAgentSessionEvent) -> Bool {
        guard event.type == "tool_execution_update", let toolCallId = event.toolCallId else { return false }
        if let index = toolUpdates.firstIndex(where: { $0.toolCallId == toolCallId }) {
            toolUpdates[index] = ToolUpdate(toolCallId: toolCallId, event: event)
            return true
        }
        toolUpdates.append(ToolUpdate(toolCallId: toolCallId, event: event))
        return true
    }

    mutating func drainToolUpdates() -> [KajiAgentSessionEvent] {
        let events = toolUpdates.map(\.event)
        toolUpdates.removeAll(keepingCapacity: true)
        return events
    }

    mutating func removeAll() {
        assistantDeltas.removeAll(keepingCapacity: false)
        toolUpdates.removeAll(keepingCapacity: false)
    }

    private struct AssistantDeltaKey: Hashable {
        let type: String
        let contentIndex: Int?
    }

    private struct AssistantDelta: Hashable {
        let key: AssistantDeltaKey
        var delta: String
    }

    private struct ToolUpdate: Hashable {
        let toolCallId: String
        var event: KajiAgentSessionEvent
    }
}

extension KajiAgentAssistantMessageEvent {
    init(type: String, delta: String?, contentIndex: Int?, toolCall: KajiAgentToolCall? = nil) {
        self.type = type
        self.delta = delta
        self.contentIndex = contentIndex
        self.toolCall = toolCall
    }

    var isTimelineTextDelta: Bool {
        type == "text_delta" || type == "thinking_delta"
    }
}
