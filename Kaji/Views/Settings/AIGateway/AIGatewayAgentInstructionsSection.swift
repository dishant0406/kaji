import AppKit
import SwiftUI

struct AIGatewayAgentInstructionsSection: View {
    let settings: AIGatewaySettings
    let tokenProvider: () -> String
    let onApplyClaude: () -> Void
    let onApplyCodex: () -> Void
    @State private var copied: String?

    var body: some View {
        SettingsSection(
            "Connect Agents",
            footer: "Kaji-launched terminals receive gateway environment variables automatically while the gateway is enabled."
        ) {
            instructionRow(
                AIGatewayAgentInstruction(
                    title: "Claude Code",
                    detail: settings.anthropicBaseURL,
                    applyTitle: "Apply Models",
                    copyTitle: "Copy Shell"
                ),
                apply: onApplyClaude,
                copy: { copy(AIGatewayInstructionBuilder.claude(settings: settings, token: tokenProvider()), label: "Claude") }
            )
            Divider().padding(.horizontal, SettingsMetrics.horizontalPadding)
            instructionRow(
                AIGatewayAgentInstruction(
                    title: "Codex",
                    detail: settings.openAIBaseURL,
                    applyTitle: "Apply Config",
                    copyTitle: "Copy Shell"
                ),
                apply: onApplyCodex,
                copy: { copy(AIGatewayInstructionBuilder.codex(settings: settings, token: tokenProvider()), label: "Codex") }
            )
            Divider().padding(.horizontal, SettingsMetrics.horizontalPadding)
            HStack(spacing: 8) {
                Text(copied ?? "Manual endpoints are available for any Anthropic or OpenAI Responses compatible client.")
                    .kajiFont(size: SettingsMetrics.footnoteFontSize)
                    .foregroundStyle(KajiTheme.fgMuted)
                Spacer(minLength: 0)
                Button(
                    "Copy Anthropic",
                    action: { copy(
                        AIGatewayInstructionBuilder.genericAnthropic(settings: settings, token: tokenProvider()),
                        label: "Anthropic"
                    )
                    }
                )
                .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                Button(
                    "Copy OpenAI",
                    action: { copy(AIGatewayInstructionBuilder.genericOpenAI(settings: settings, token: tokenProvider()), label: "OpenAI") }
                )
                .buttonStyle(KajiButtonStyle(.secondary, size: .small))
            }
            .padding(.horizontal, SettingsMetrics.horizontalPadding)
            .padding(.vertical, SettingsMetrics.rowVerticalPadding + 4)
        }
    }

    private func instructionRow(
        _ instruction: AIGatewayAgentInstruction,
        apply: @escaping () -> Void,
        copy: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            KajiIcon(systemName: "terminal", size: 15).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(instruction.title)
                    .kajiFont(size: SettingsMetrics.labelFontSize, weight: .medium)
                    .foregroundStyle(KajiTheme.fg)
                Text(instruction.detail)
                    .kajiFont(size: SettingsMetrics.footnoteFontSize, design: .monospaced)
                    .foregroundStyle(KajiTheme.fgMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(instruction.applyTitle, action: apply)
                .buttonStyle(KajiButtonStyle(.secondary, size: .small))
            Button(instruction.copyTitle, action: copy)
                .buttonStyle(KajiButtonStyle(.secondary, size: .small))
        }
        .padding(.horizontal, SettingsMetrics.horizontalPadding)
        .padding(.vertical, SettingsMetrics.rowVerticalPadding + 4)
    }

    private func copy(_ text: String, label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = "Copied \(label) gateway instructions."
    }
}

private struct AIGatewayAgentInstruction {
    let title: String
    let detail: String
    let applyTitle: String
    let copyTitle: String
}
