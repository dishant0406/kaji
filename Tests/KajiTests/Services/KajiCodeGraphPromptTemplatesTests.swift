import Testing

@testable import Kaji

struct KajiCodeGraphPromptTemplatesTests {
    @Test
    func codeGraphDocumentUsesUserManagedMCPInstructions() {
        let text = KajiCodeGraphPromptTemplates.codeGraphDocument

        #expect(text.contains("CODE_GRAPH") == false)
        #expect(text.contains("code_graph_status"))
        #expect(text.contains("code_graph_search"))
        #expect(text.contains("code_graph_hotspots"))
        #expect(!text.contains("/Users/"))
        #expect(!text.contains("~/.kaji/extensions/kajicodegraph/projects"))
    }

    @Test
    func referenceSnippetsPointAtCodeGraphDocument() {
        #expect(KajiCodeGraphPromptTemplates.agentsReference.contains("@CODE_GRAPH.md"))
        #expect(KajiCodeGraphPromptTemplates.claudeReference.contains("@CODE_GRAPH.md"))
    }
}
