import SwiftUI

struct KajiAgentLongTextView: View {
    let content: String
    var size: CGFloat = KajiAgentTranscriptMetrics.assistantFont
    var color: Color = KajiTheme.fg
    var threshold = 8000
    @State private var expanded = false

    var body: some View {
        if content.count <= threshold || expanded {
            KajiAgentMarkdownText(content: content, size: size, color: color)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                KajiAgentMarkdownText(content: preview, size: size, color: color)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Show full text (\(content.count) characters)") {
                    expanded = true
                }
                .buttonStyle(KajiButtonStyle(.secondary, size: .small))
            }
        }
    }

    private var preview: String {
        String(content.prefix(threshold)) + "\n\n... truncated"
    }
}
