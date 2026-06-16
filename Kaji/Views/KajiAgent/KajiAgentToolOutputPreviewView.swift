import SwiftUI

struct KajiAgentToolOutputPreviewView: View {
    let output: String
    let toolName: String
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !preview.isEmpty {
                Text(preview)
                    .font(.system(size: KajiAgentTranscriptMetrics.codeFont, design: .monospaced))
                    .lineSpacing(2)
                    .foregroundStyle(KajiTheme.fgMuted)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(KajiTheme.bg.opacity(0.56), in: RoundedRectangle(cornerRadius: KajiAgentTranscriptMetrics.controlRadius))
            }
            Button(action: onOpen) {
                HStack(spacing: 6) {
                    KajiIcon(systemName: "sidebar.right", size: 10)
                    Text("Open full \(toolName) output")
                        .kajiFont(size: 11.5, weight: .medium)
                }
                .foregroundStyle(KajiTheme.fgMuted)
            }
            .buttonStyle(.plain)
            .kajiPointer()
        }
    }

    private var preview: String {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).prefix(12)
        let value = lines.joined(separator: "\n")
        guard output.split(separator: "\n", omittingEmptySubsequences: false).count > 12 else { return value }
        return value + "\n..."
    }
}
