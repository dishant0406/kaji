import Testing

@testable import Kaji

struct MarkdownPreviewResourceLoaderTests {
    @Test
    func shellIncludesRuntimeAssets() {
        let html = MarkdownPreviewResourceLoader.shellHTML()

        #expect(html.contains("window.KajiMarkdownPreview"))
        #expect(html.contains("markdownit"))
        #expect(html.contains("DOMPurify"))
        #expect(html.contains("mermaid"))
        #expect(html.contains("renderMathInElement"))
        #expect(html.contains("kaji-preview-asset:///KaTeX_"))
        #expect(html.contains("kaji-managed-block"))
        #expect(!html.contains("{{STYLE}}"))
        #expect(!html.contains("{{SCRIPTS}}"))
    }
}
