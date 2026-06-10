import AppKit
import SwiftUI

struct KajiAgentCodeBlockView: View {
    let code: String
    let language: String?
    @State private var copied = false
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(.system(size: KajiAgentTranscriptMetrics.codeFont, design: .monospaced))
                    .lineSpacing(3)
                    .foregroundStyle(KajiTheme.fg)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: KajiAgentTranscriptMetrics.codeMaxHeight)
        }
        .background(KajiTheme.bg.opacity(0.74), in: RoundedRectangle(cornerRadius: KajiAgentTranscriptMetrics.controlRadius))
        .overlay(RoundedRectangle(cornerRadius: KajiAgentTranscriptMetrics.controlRadius).stroke(KajiTheme.border.opacity(0.75)))
        .onHover { hovered = $0 }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(languageLabel)
                .kajiFont(size: KajiAgentTranscriptMetrics.toolDetailFont, weight: .medium)
                .foregroundStyle(KajiTheme.fgDim)
            Spacer(minLength: 0)
            Button(copied ? "Copied" : "Copy") { copy() }
                .buttonStyle(.plain)
                .kajiFont(size: KajiAgentTranscriptMetrics.toolDetailFont, weight: .medium)
                .foregroundStyle(hovered || copied ? KajiTheme.fgMuted : KajiTheme.fgDim)
                .kajiPointer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(KajiTheme.secondaryBackground.opacity(0.72))
    }

    private var languageLabel: String {
        language?.nilIfEmpty ?? "text"
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        copied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            copied = false
        }
    }
}
