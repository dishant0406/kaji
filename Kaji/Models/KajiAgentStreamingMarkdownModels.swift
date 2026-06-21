import Foundation

struct KajiAgentStreamingMarkdownBlock: Hashable, Identifiable {
    let id: String
    let content: String
    let isLive: Bool
}

struct KajiAgentStreamingMarkdownRenderedBlock: Hashable, Identifiable {
    let id: String
    let blocks: [KajiAgentMarkdownBlock]
    let isLive: Bool
}

struct KajiAgentStreamingMarkdownSnapshot: Hashable {
    let blocks: [KajiAgentStreamingMarkdownRenderedBlock]

    static let empty = KajiAgentStreamingMarkdownSnapshot(blocks: [])
}
