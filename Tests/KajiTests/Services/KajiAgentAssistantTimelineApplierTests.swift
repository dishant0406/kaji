import Foundation
import Testing

@testable import Kaji

struct KajiAgentAssistantTimelineApplierTests {
    @Test
    func appendsAssistantStartPartsInContentOrder() {
        var state = State()

        KajiAgentAssistantTimelineApplier.appendStart(
            content: .array([
                .object(["type": .string("text"), "text": .string("Answer")]),
                .object(["type": .string("thinking"), "thinking": .string("Plan")]),
            ]),
            turns: &state.turns,
            activeTurnID: &state.activeTurnID,
            tailVersion: &state.tailVersion
        )

        #expect(state.messages.map(\.kind) == [.assistant, .thinking])
        #expect(state.messages.map(\.detail) == ["Answer", "Plan"])
        #expect(state.messages.allSatisfy { !$0.isComplete })
    }

    @Test
    func textDeltaUpdatesMatchingOpenAssistantBlock() throws {
        var state = State()
        KajiAgentAssistantTimelineApplier.appendStart(
            content: .array([.object(["type": .string("text"), "text": .string("Hel")])]),
            turns: &state.turns,
            activeTurnID: &state.activeTurnID,
            tailVersion: &state.tailVersion
        )

        KajiAgentAssistantTimelineApplier.apply(
            update: .test(type: "text_delta", delta: "lo", contentIndex: 0),
            turns: &state.turns,
            activeTurnID: &state.activeTurnID,
            tailVersion: &state.tailVersion
        )

        let message = try #require(state.messages.first)
        #expect(message.detail == "Hello")
        #expect(message.isComplete == false)
    }

    @Test
    func thinkingDeltaRequiresActiveTailThinkingBlock() throws {
        var state = State()
        KajiAgentAssistantTimelineApplier.apply(
            update: .test(type: "thinking_delta", delta: "Plan", contentIndex: 0),
            turns: &state.turns,
            activeTurnID: &state.activeTurnID,
            tailVersion: &state.tailVersion
        )
        KajiAgentTimeline.appendResponseMessage(
            KajiAgentMessage(kind: .assistant, title: "Kaji", detail: "Visible"),
            turns: &state.turns,
            activeTurnID: &state.activeTurnID,
            tailVersion: &state.tailVersion
        )
        KajiAgentAssistantTimelineApplier.apply(
            update: .test(type: "thinking_delta", delta: " later", contentIndex: 0),
            turns: &state.turns,
            activeTurnID: &state.activeTurnID,
            tailVersion: &state.tailVersion
        )

        #expect(state.messages.map(\.kind) == [.thinking, .assistant, .thinking])
        #expect(state.messages.map(\.detail) == ["Plan", "Visible", " later"])
    }

    @Test
    func finishAssistantCompletesOpenAssistantAndThinkingBlocks() throws {
        var state = State()
        KajiAgentAssistantTimelineApplier.appendStart(
            content: .array([
                .object(["type": .string("thinking"), "thinking": .string("Draft")]),
                .object(["type": .string("text"), "text": .string("Part")]),
            ]),
            turns: &state.turns,
            activeTurnID: &state.activeTurnID,
            tailVersion: &state.tailVersion
        )

        KajiAgentAssistantTimelineApplier.finishAssistant(
            content: .array([
                .object(["type": .string("thinking"), "thinking": .string("Final thought")]),
                .object(["type": .string("text"), "text": .string("Final answer")]),
            ]),
            errorMessage: nil,
            turns: &state.turns,
            activeTurnID: &state.activeTurnID,
            tailVersion: &state.tailVersion
        )

        #expect(state.messages.map(\.detail) == ["Final thought", "Final answer"])
        let allComplete = state.messages.allSatisfy { $0.isComplete }
        #expect(allComplete)
    }

    @Test
    func finishAssistantAppendsProviderError() throws {
        var state = State()

        KajiAgentAssistantTimelineApplier.finishAssistant(
            content: .string(""),
            errorMessage: "rate limited",
            turns: &state.turns,
            activeTurnID: &state.activeTurnID,
            tailVersion: &state.tailVersion
        )

        let message = try #require(state.messages.first)
        #expect(message.kind == .error)
        #expect(message.title == "Provider error")
        #expect(message.detail == "rate limited")
    }

    private struct State {
        var turns: [KajiAgentTurn] = []
        var activeTurnID: KajiAgentTurn.ID?
        var tailVersion = 0

        var messages: [KajiAgentMessage] { turns.flatMap(\.messages) }
    }
}

private extension KajiAgentAssistantMessageEvent {
    static func test(type: String, delta: String?, contentIndex: Int?) -> KajiAgentAssistantMessageEvent {
        try! JSONDecoder().decode(KajiAgentAssistantMessageEvent.self, from: Data(
            #"{"type":"\#(type)","delta":"\#(delta ?? "")","contentIndex":\#(contentIndex ?? 0)}"#.utf8
        ))
    }
}
