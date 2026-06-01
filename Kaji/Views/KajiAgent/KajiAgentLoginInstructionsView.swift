import AppKit
import SwiftUI

struct KajiAgentLoginInstructionsView: View {
    @Bindable var store: KajiAgentStore

    var body: some View {
        if store.loginCode != nil || store.loginInstructions != nil || store.loginURL != nil {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    KajiIcon(systemName: "person.badge.key", size: 12)
                        .foregroundStyle(KajiTheme.fgMuted)
                    Text("Complete login")
                        .kajiFont(size: 12, weight: .semibold)
                        .foregroundStyle(KajiTheme.fg)
                    Spacer(minLength: 0)
                }
                if let code = store.loginCode {
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
                if let instructions = store.loginInstructions, !instructions.isEmpty {
                    Text(instructions)
                        .kajiFont(size: 12)
                        .foregroundStyle(KajiTheme.fgMuted)
                        .textSelection(.enabled)
                        .lineLimit(nil)
                }
                if let url = store.loginURL, let parsed = URL(string: url) {
                    Button("Open browser") { NSWorkspace.shared.open(parsed) }
                        .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KajiTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
