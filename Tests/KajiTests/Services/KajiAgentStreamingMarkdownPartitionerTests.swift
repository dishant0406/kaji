import Foundation
import Testing

@testable import Kaji

struct KajiAgentStreamingMarkdownPartitionerTests {
    @Test
    func keepsOnlyTailParagraphLive() throws {
        let messageID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let blocks = KajiAgentStreamingMarkdownPartitioner.blocks(
            messageID: messageID,
            content: "# Title\n\nStreaming **bo",
            isComplete: false
        )

        #expect(blocks.map(\.isLive) == [false, true])
        #expect(blocks.map(\.content) == ["# Title", "Streaming **bo"])
    }

    @Test
    func freezesClosedFenceAtTail() throws {
        let messageID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let blocks = KajiAgentStreamingMarkdownPartitioner.blocks(
            messageID: messageID,
            content: "```swift\nlet value = 1\n```",
            isComplete: false
        )

        #expect(blocks.count == 1)
        #expect(blocks[0].isLive == false)
    }

    @Test
    func marksOpenFenceLive() throws {
        let messageID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        let blocks = KajiAgentStreamingMarkdownPartitioner.blocks(
            messageID: messageID,
            content: "```swift\nlet value = 1",
            isComplete: false
        )

        #expect(blocks.count == 1)
        #expect(blocks[0].isLive)
    }
}
