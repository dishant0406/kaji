import Testing

@testable import Kaji

struct KajiAgentTranscriptVirtualizationPolicyTests {
    @Test
    func keepsShortTranscriptInLiveTail() {
        let turns = makeTurns(2)

        let sections = KajiAgentTranscriptVirtualizationPolicy.split(turns)

        #expect(sections.history.isEmpty)
        #expect(sections.liveTail.map(\.id) == turns.map(\.id))
    }

    @Test
    func virtualizesOlderTurnsAndKeepsRecentTailLive() {
        let turns = makeTurns(6)

        let sections = KajiAgentTranscriptVirtualizationPolicy.split(turns)

        #expect(sections.history.map(\.id) == turns.prefix(3).map(\.id))
        #expect(sections.liveTail.map(\.id) == turns.suffix(3).map(\.id))
    }

    private func makeTurns(_ count: Int) -> [KajiAgentTurn] {
        (0..<count).map { index in
            KajiAgentTurn(user: KajiAgentMessage(kind: .user, title: "You", detail: "Turn \(index)"))
        }
    }
}
