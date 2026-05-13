import SwiftUI

struct InlineEditDiffPreview: View {
    let original: String
    let proposal: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Preview")
                    .kajiFont(size: 11, weight: .semibold)
                    .foregroundStyle(KajiTheme.fgMuted)
                Spacer()
                Text(summary)
                    .kajiFont(size: 10)
                    .foregroundStyle(KajiTheme.fgDim)
            }
            HStack(spacing: 8) {
                diffColumn(title: "Selection", text: original, color: KajiTheme.diffRemoveFg)
                diffColumn(title: "Replacement", text: proposal, color: KajiTheme.diffAddFg)
            }
        }
    }

    private var summary: String {
        let originalLines = original.components(separatedBy: .newlines).count
        let proposalLines = proposal.components(separatedBy: .newlines).count
        return "\(originalLines) -> \(proposalLines) lines"
    }

    private func diffColumn(title: String, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .kajiFont(size: 10, weight: .medium)
                .foregroundStyle(color)
            ScrollView {
                Text(previewText(text))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(KajiTheme.fg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(height: 96)
            .padding(8)
            .background(KajiTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.18), lineWidth: 1))
        }
    }

    private func previewText(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        guard lines.count > 8 else { return text }
        return lines.prefix(8).joined(separator: "\n") + "\n..."
    }
}
