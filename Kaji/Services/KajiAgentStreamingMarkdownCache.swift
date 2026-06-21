import Foundation

@MainActor
final class KajiAgentStreamingMarkdownCache {
    static let shared = KajiAgentStreamingMarkdownCache()
    private var entries: [CacheKey: [KajiAgentMarkdownBlock]] = [:]
    private var order: [CacheKey] = []
    private let limit: Int

    init(limit: Int = 320) {
        self.limit = max(1, limit)
    }

    func snapshot(messageID: UUID, content: String, isComplete: Bool) -> KajiAgentStreamingMarkdownSnapshot {
        let sourceBlocks = KajiAgentStreamingMarkdownPartitioner.blocks(
            messageID: messageID,
            content: content,
            isComplete: isComplete
        )
        let rendered = sourceBlocks.map { block in
            let parsed = parsedBlocks(for: block)
            return KajiAgentStreamingMarkdownRenderedBlock(id: block.id, blocks: parsed, isLive: block.isLive)
        }
        return KajiAgentStreamingMarkdownSnapshot(blocks: rendered)
    }

    func contains(id: String, content: String, isLive: Bool) -> Bool {
        entries[CacheKey(id: id, content: content, isLive: isLive)] != nil
    }

    private func parsedBlocks(for block: KajiAgentStreamingMarkdownBlock) -> [KajiAgentMarkdownBlock] {
        let content = block.isLive ? KajiAgentStreamingMarkdownHealer.heal(block.content) : block.content
        let key = CacheKey(id: block.id, content: content, isLive: block.isLive)
        if let cached = entries[key] {
            promote(key)
            return cached
        }
        let parsed = KajiAgentMarkdownParser.parse(content)
        entries[key] = parsed
        order.append(key)
        trim()
        return parsed
    }

    private func promote(_ key: CacheKey) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    private func trim() {
        while order.count > limit {
            let removed = order.removeFirst()
            entries.removeValue(forKey: removed)
        }
    }

    private struct CacheKey: Hashable {
        let id: String
        let content: String
        let isLive: Bool
    }
}
