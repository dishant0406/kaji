import AppKit
import SwiftUI

struct AgentSettingsLoginInstructionsView: View {
    let code: String?
    let instructions: String?
    let url: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let code {
                HStack(spacing: 8) {
                    Text(code)
                        .kajiFont(size: 18, weight: .semibold, design: .monospaced)
                        .foregroundStyle(KajiTheme.fg)
                        .textSelection(.enabled)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(KajiTheme.bg.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
                    Button("Copy") { copy(code) }
                        .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                }
            }
            if let instructions, !instructions.isEmpty {
                Text(instructions)
                    .kajiFont(size: 12)
                    .foregroundStyle(KajiTheme.fgMuted)
                    .textSelection(.enabled)
                    .lineLimit(nil)
            }
            if let url, let parsed = URL(string: url) {
                Button("Open browser") { NSWorkspace.shared.open(parsed) }
                    .buttonStyle(KajiButtonStyle(.secondary, size: .small))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KajiTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 12))
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
