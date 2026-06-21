import Testing
@testable import Kaji

@MainActor
struct KajiAgentMarkdownRenderCacheTests {
    @Test func reusesCachedParsedBlocks() {
        let cache = KajiAgentMarkdownRenderCache(limit: 2)
        let content = "# Title\n\n- One\n- Two"

        let first = cache.blocks(for: content)
        let second = cache.blocks(for: content)

        #expect(first == second)
        #expect(cache.contains(content))
    }

    @Test func evictsLeastRecentlyUsedBlock() {
        let cache = KajiAgentMarkdownRenderCache(limit: 2)
        _ = cache.blocks(for: "one")
        _ = cache.blocks(for: "two")
        _ = cache.blocks(for: "one")
        _ = cache.blocks(for: "three")

        #expect(cache.contains("one"))
        #expect(!cache.contains("two"))
        #expect(cache.contains("three"))
    }
}
