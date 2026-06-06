import Foundation
import Testing

@testable import Kaji

struct KajiAgentTimelineTests {
    @Test
    func startTurnReusesEmptyActiveTurn() throws {
        var turns: [KajiAgentTurn] = []
        var activeTurnID: KajiAgentTurn.ID?
        var tailVersion = 0

        KajiAgentTimeline.ensureActiveTurn(turns: &turns, activeTurnID: &activeTurnID)
        KajiAgentTimeline.startTurn(
            user: KajiAgentMessage(kind: .user, title: "You", detail: "Hi"),
            turns: &turns,
            activeTurnID: &activeTurnID,
            tailVersion: &tailVersion
        )

        #expect(turns.count == 1)
        #expect(turns[0].user?.detail == "Hi")
        #expect(activeTurnID == turns[0].id)
        #expect(tailVersion == 1)
    }

    @Test
    func groupsAdjacentToolsAndStartsNewGroupAfterMessage() throws {
        var turns: [KajiAgentTurn] = []
        var activeTurnID: KajiAgentTurn.ID?
        var tailVersion = 0

        KajiAgentTimeline.appendToolToActiveGroup(tool("read"), turns: &turns, activeTurnID: &activeTurnID, tailVersion: &tailVersion)
        KajiAgentTimeline.appendToolToActiveGroup(tool("bash"), turns: &turns, activeTurnID: &activeTurnID, tailVersion: &tailVersion)
        KajiAgentTimeline.appendResponseMessage(
            KajiAgentMessage(kind: .assistant, title: "Kaji", detail: "Done"),
            turns: &turns,
            activeTurnID: &activeTurnID,
            tailVersion: &tailVersion
        )
        KajiAgentTimeline.appendToolToActiveGroup(tool("write"), turns: &turns, activeTurnID: &activeTurnID, tailVersion: &tailVersion)

        #expect(turns.count == 1)
        #expect(turns[0].blocks.count == 3)
        guard case let .toolGroup(firstGroup) = turns[0].blocks[0],
              case let .toolGroup(secondGroup) = turns[0].blocks[2]
        else {
            Issue.record("Expected tool groups around assistant message")
            return
        }
        #expect(firstGroup.tools.map(\.title) == ["read", "bash"])
        #expect(secondGroup.tools.map(\.title) == ["write"])
        #expect(tailVersion == 4)
    }

    @Test
    func findsAndUpdatesLatestMatchingTool() throws {
        var turns: [KajiAgentTurn] = []
        var activeTurnID: KajiAgentTurn.ID?
        var tailVersion = 0

        KajiAgentTimeline.startTurn(user: KajiAgentMessage(kind: .user, title: "You", detail: "Run"), turns: &turns, activeTurnID: &activeTurnID, tailVersion: &tailVersion)
        KajiAgentTimeline.appendToolToActiveGroup(tool("bash", id: "tool-1"), turns: &turns, activeTurnID: &activeTurnID, tailVersion: &tailVersion)
        let location = try #require(KajiAgentTimeline.toolLocation(turns: turns, activeTurnID: activeTurnID) { $0.toolCallID == "tool-1" })

        KajiAgentTimeline.updateTool(at: location, turns: &turns) { tool in
            tool.detail = "complete"
            tool.isComplete = true
        }

        let updated = try #require(KajiAgentTimeline.tool(at: location, turns: turns))
        #expect(updated.detail == "complete")
        #expect(updated.isComplete)
    }

    @Test
    func activeTailMessageRequiresActiveLastBlock() {
        var turns: [KajiAgentTurn] = []
        var activeTurnID: KajiAgentTurn.ID?
        var tailVersion = 0

        KajiAgentTimeline.appendResponseMessage(
            KajiAgentMessage(kind: .thinking, title: "Thinking", detail: "A", isComplete: false),
            turns: &turns,
            activeTurnID: &activeTurnID,
            tailVersion: &tailVersion
        )
        let found = KajiAgentTimeline.activeTailMessageLocation(turns: turns, activeTurnID: activeTurnID) { $0.kind == .thinking }
        KajiAgentTimeline.appendToolToActiveGroup(tool("bash"), turns: &turns, activeTurnID: &activeTurnID, tailVersion: &tailVersion)
        let missing = KajiAgentTimeline.activeTailMessageLocation(turns: turns, activeTurnID: activeTurnID) { $0.kind == .thinking }

        #expect(found != nil)
        #expect(missing == nil)
    }

    private func tool(_ name: String, id: String = UUID().uuidString) -> KajiAgentMessage {
        KajiAgentMessage(kind: .tool, title: name, detail: "", toolCallID: id, isComplete: false)
    }
}
