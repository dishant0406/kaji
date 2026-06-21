import SwiftUI

struct KajiAgentMarkdownBlocksView: View {
    let blocks: [KajiAgentMarkdownBlock]
    var size: CGFloat = KajiAgentTranscriptMetrics.assistantFont
    var color: Color = KajiTheme.fg

    var body: some View {
        VStack(alignment: .leading, spacing: KajiAgentTranscriptMetrics.paragraphSpacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: KajiAgentMarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            KajiAgentInlineText(content: text, size: headingSize(level), color: KajiTheme.fg)
                .fontWeight(.semibold)
                .padding(.top, level == 1 ? 6 : 2)
        case let .paragraph(text):
            KajiAgentInlineText(content: text, size: size, color: color)
        case let .bullets(items):
            list(items: items, ordered: false)
        case let .ordered(items):
            list(items: items, ordered: true)
        case let .quote(text):
            HStack(alignment: .top, spacing: 10) {
                Rectangle().fill(KajiTheme.borderStrong.opacity(0.7)).frame(width: 2)
                KajiAgentInlineText(content: text, size: size, color: KajiTheme.fgMuted)
            }
            .padding(.vertical, 2)
        case let .code(language, text):
            KajiAgentCodeBlockView(code: text, language: language)
        case .divider:
            Rectangle().fill(KajiTheme.border.opacity(0.8)).frame(height: 1).padding(.vertical, 3)
        }
    }

    private func list(items: [String], ordered: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 10) {
                    Text(ordered ? "\(index + 1)." : "•")
                        .kajiFont(size: size)
                        .foregroundStyle(KajiTheme.fgDim)
                        .frame(width: ordered ? 24 : 14, alignment: .trailing)
                    KajiAgentInlineText(content: item, size: size, color: color)
                }
            }
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: size + 3
        case 2: size + 2
        case 3: size + 1
        default: size
        }
    }
}
