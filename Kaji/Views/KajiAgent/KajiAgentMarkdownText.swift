import SwiftUI

struct KajiAgentMarkdownText: View {
    let content: String
    var size: CGFloat = KajiAgentTranscriptMetrics.assistantFont
    var color: Color = KajiTheme.fg

    var body: some View {
        KajiAgentMarkdownBlocksView(blocks: blocks, size: size, color: color)
    }

    private var blocks: [KajiAgentMarkdownBlock] {
        KajiAgentMarkdownRenderCache.shared.blocks(for: content)
    }
}
