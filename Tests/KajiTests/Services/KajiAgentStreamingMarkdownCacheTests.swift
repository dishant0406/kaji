import Foundation
import Testing

@testable import Kaji

@MainActor
struct KajiAgentStreamingMarkdownCacheTests {
    @Test
    func rendersStableAndLiveBlocksSeparately() throws {
        let cache = KajiAgentStreamingMarkdownCache(limit: 8)
        let messageID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000004"))

        let snapshot = cache.snapshot(
            messageID: messageID,
            content: "# Done\n\nNow **stream",
            isComplete: false
        )

        #expect(snapshot.blocks.count == 2)
        #expect(snapshot.blocks[0].blocks == [.heading(level: 1, text: "Done")])
        #expect(snapshot.blocks[1].blocks == [.paragraph("Now **stream**")])
        #expect(snapshot.blocks[1].isLive)
    }

    @Test
    func reusesStableBlockCacheAcrossTailChanges() throws {
        let cache = KajiAgentStreamingMarkdownCache(limit: 8)
        let messageID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000005"))
        let content = "# Done\n\nNow streaming"
        let first = cache.snapshot(messageID: messageID, content: content, isComplete: false)
        let second = cache.snapshot(messageID: messageID, content: content + " more", isComplete: false)

        #expect(first.blocks[0].blocks == second.blocks[0].blocks)
        #expect(cache.contains(id: first.blocks[0].id, content: "# Done", isLive: false))
    }
}
