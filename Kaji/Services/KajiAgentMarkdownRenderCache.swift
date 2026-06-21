import Foundation

@MainActor
final class KajiAgentMarkdownRenderCache {
    static let shared = KajiAgentMarkdownRenderCache()
    private var entries: [String: [KajiAgentMarkdownBlock]] = [:]
    private var order: [String] = []
    private let limit: Int

    init(limit: Int = 160) {
        self.limit = max(1, limit)
    }

    func blocks(for content: String) -> [KajiAgentMarkdownBlock] {
        if let cached = entries[content] {
            promote(content)
            return cached
        }
        let parsed = KajiAgentMarkdownParser.parse(content)
        entries[content] = parsed
        order.append(content)
        trim()
        return parsed
    }

    func contains(_ content: String) -> Bool {
        entries[content] != nil
    }

    private func promote(_ key: String) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    private func trim() {
        while order.count > limit {
            let removed = order.removeFirst()
            entries.removeValue(forKey: removed)
        }
    }
}
