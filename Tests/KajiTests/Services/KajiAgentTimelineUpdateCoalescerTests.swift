import Testing

@testable import Kaji

@MainActor
struct KajiAgentTimelineUpdateCoalescerTests {
    @Test
    func coalescesAdjacentAssistantDeltasWithSameKey() {
        var coalescer = KajiAgentTimelineUpdateCoalescer()

        let firstAccepted = coalescer.enqueueAssistantDelta(.init(type: "text_delta", delta: "Hel", contentIndex: 0))
        let secondAccepted = coalescer.enqueueAssistantDelta(.init(type: "text_delta", delta: "lo", contentIndex: 0))

        #expect(firstAccepted)
        #expect(secondAccepted)

        let updates = coalescer.drainAssistantDeltas()

        #expect(updates.count == 1)
        #expect(updates.first?.type == "text_delta")
        #expect(updates.first?.delta == "Hello")
        #expect(updates.first?.contentIndex == 0)
        #expect(!coalescer.hasPendingAssistantDeltas)
    }

    @Test
    func preservesAssistantDeltaOrderAcrossDifferentKeys() {
        var coalescer = KajiAgentTimelineUpdateCoalescer()

        _ = coalescer.enqueueAssistantDelta(.init(type: "thinking_delta", delta: "Plan", contentIndex: 0))
        _ = coalescer.enqueueAssistantDelta(.init(type: "text_delta", delta: "Answer", contentIndex: 1))
        _ = coalescer.enqueueAssistantDelta(.init(type: "thinking_delta", delta: " more", contentIndex: 0))

        let updates = coalescer.drainAssistantDeltas()

        #expect(updates.map(\.type) == ["thinking_delta", "text_delta", "thinking_delta"])
        #expect(updates.map(\.delta) == ["Plan", "Answer", " more"])
    }

    @Test
    func keepsOnlyLatestToolUpdatePerToolCall() {
        var coalescer = KajiAgentTimelineUpdateCoalescer()
        let first = KajiAgentSessionEvent(
            type: "tool_execution_update",
            toolCallId: "tool-1",
            toolName: "bash",
            partialResult: KajiAgentToolResult(content: [.init(type: "text", text: "one")])
        )
        let second = KajiAgentSessionEvent(
            type: "tool_execution_update",
            toolCallId: "tool-1",
            toolName: "bash",
            partialResult: KajiAgentToolResult(content: [.init(type: "text", text: "two")])
        )

        let firstAccepted = coalescer.enqueueToolUpdate(first)
        let secondAccepted = coalescer.enqueueToolUpdate(second)

        #expect(firstAccepted)
        #expect(secondAccepted)

        let updates = coalescer.drainToolUpdates()

        #expect(updates.count == 1)
        #expect(updates.first?.partialResult?.content.first?.text == "two")
        #expect(!coalescer.hasPendingToolUpdates)
    }
}
