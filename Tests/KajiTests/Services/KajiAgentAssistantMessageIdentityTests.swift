import Testing

@testable import Kaji

struct KajiAgentAssistantMessageIdentityTests {
    @Test
    func repeatedThinkingRoundsInSameTurnKeepDistinctIDs() throws {
        var state = KajiAgentAssistantIdentityState.started()
        KajiAgentAssistantTimelineApplier.apply(
            update: .test(type: "thinking_delta", delta: "First", contentIndex: 0),
            turns: &state.turns,
            activeTurnID: &state.activeTurnID,
            tailVersion: &state.tailVersion
        )
        KajiAgentAssistantTimelineApplier.finishAssistant(
            content: nil,
            errorMessage: nil,
            turns: &state.turns,
            activeTurnID: &state.activeTurnID,
            tailVersion: &state.tailVersion
        )
        KajiAgentAssistantTimelineApplier.apply(
            update: .test(type: "thinking_delta", delta: "Second", contentIndex: 0),
            turns: &state.turns,
            activeTurnID: &state.activeTurnID,
            tailVersion: &state.tailVersion
        )

        let ids = state.messages.filter { $0.kind == .thinking }.map(\.id)

        #expect(ids.count == 2)
        #expect(Set(ids).count == 2)
    }

    @Test
    func repeatedTextRoundsInSameTurnKeepDistinctIDs() throws {
        var state = KajiAgentAssistantIdentityState.started()
        KajiAgentAssistantTimelineApplier.apply(
            update: .test(type: "text_delta", delta: "First", contentIndex: 0),
            turns: &state.turns,
            activeTurnID: &state.activeTurnID,
            tailVersion: &state.tailVersion
        )
        KajiAgentAssistantTimelineApplier.finishAssistant(
            content: .array([.object(["type": .string("text"), "text": .string("First")])]),
            errorMessage: nil,
            turns: &state.turns,
            activeTurnID: &state.activeTurnID,
            tailVersion: &state.tailVersion
        )
        KajiAgentAssistantTimelineApplier.apply(
            update: .test(type: "text_delta", delta: "Second", contentIndex: 0),
            turns: &state.turns,
            activeTurnID: &state.activeTurnID,
            tailVersion: &state.tailVersion
        )

        let ids = state.messages.filter { $0.kind == .assistant }.map(\.id)

        #expect(ids.count == 2)
        #expect(Set(ids).count == 2)
    }

}

private struct KajiAgentAssistantIdentityState {
    var turns: [KajiAgentTurn] = []
    var activeTurnID: KajiAgentTurn.ID?
    var tailVersion = 0

    var messages: [KajiAgentMessage] { turns.flatMap(\.messages) }

    static func started() -> KajiAgentAssistantIdentityState {
        var state = KajiAgentAssistantIdentityState()
        KajiAgentTimeline.startTurn(
            user: KajiAgentMessage(kind: .user, title: "You", detail: "Analyze"),
            turns: &state.turns,
            activeTurnID: &state.activeTurnID,
            tailVersion: &state.tailVersion
        )
        return state
    }
}
