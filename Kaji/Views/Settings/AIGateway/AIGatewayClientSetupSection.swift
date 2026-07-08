import SwiftUI

struct AIGatewayClientSetupSection: View {
    @Binding var draft: AIGatewaySetupDraft
    let onApplyClaude: () -> Void
    let onApplyCodex: () -> Void

    var body: some View {
        SettingsSection(
            "Use with",
            footer: "New Kaji-launched terminals receive the gateway environment automatically after setup."
        ) {
            clientRow("Claude Code", isOn: $draft.useClaude, actionTitle: "Configure", action: onApplyClaude)
            Divider().padding(.horizontal, SettingsMetrics.horizontalPadding)
            clientRow("Codex", isOn: $draft.useCodex, actionTitle: "Configure", action: onApplyCodex)
        }
    }

    private func clientRow(
        _ title: String,
        isOn: Binding<Bool>,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .kajiFont(size: SettingsMetrics.labelFontSize, weight: .medium)
                .foregroundStyle(KajiTheme.fg)
            Spacer(minLength: 0)
            Button(actionTitle, action: action)
                .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                .disabled(!isOn.wrappedValue)
            KajiSwitch(isOn: isOn)
        }
        .padding(.horizontal, SettingsMetrics.horizontalPadding)
        .padding(.vertical, SettingsMetrics.rowVerticalPadding + 4)
    }
}
