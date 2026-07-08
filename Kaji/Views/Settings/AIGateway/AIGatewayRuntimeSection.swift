import SwiftUI

struct AIGatewayRuntimeSection: View {
    let settings: AIGatewaySettings
    let status: AIGatewayRuntimeStatus
    let installState: AIGatewayInstallState
    let message: String?
    let isWorking: Bool
    let onInstall: () -> Void
    let onUninstall: () -> Void
    let onEnabled: (Bool) -> Void
    let onAutoStart: (Bool) -> Void
    let onBind: (String) -> Void
    let onPort: (Int) -> Void
    let onStart: () -> Void
    let onStop: () -> Void
    let onRestart: () -> Void
    let onRotateToken: () -> Void
    @State private var bindText = ""
    @State private var portText = ""

    var body: some View {
        SettingsSection("AI Gateway", footer: footer) {
            HStack(alignment: .center, spacing: 10) {
                KajiIcon(systemName: "point.3.connected.trianglepath.dotted", size: 16).frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Claude Code Router")
                        .kajiFont(size: SettingsMetrics.labelFontSize, weight: .medium)
                        .foregroundStyle(KajiTheme.fg)
                    Text(statusText)
                        .kajiFont(size: SettingsMetrics.footnoteFontSize)
                        .foregroundStyle(statusColor)
                    if let message {
                        Text(message)
                            .kajiFont(size: SettingsMetrics.footnoteFontSize)
                            .foregroundStyle(KajiTheme.fgDim)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                installButtons
                KajiSwitch(isOn: Binding(get: { settings.isEnabled }, set: { value in onEnabled(value) }))
                    .disabled(!usable || isWorking)
            }
            .padding(.horizontal, SettingsMetrics.horizontalPadding)
            .padding(.vertical, SettingsMetrics.rowVerticalPadding + 4)

            SettingsDetailToggleRow(
                label: "Auto start",
                detail: "Start the local gateway when Kaji opens.",
                isOn: Binding(get: { settings.autoStart }, set: { value in onAutoStart(value) })
            )
            .disabled(!settings.isEnabled)

            SettingsRow("Bind") {
                HStack(spacing: 8) {
                    KajiInput(placeholder: "127.0.0.1", text: $bindText, width: 130, monospaced: true)
                    KajiInput(placeholder: "5254", text: $portText, width: 70, monospaced: true)
                }
            }
            .onChange(of: bindText) { _, value in onBind(value) }
            .onChange(of: portText) { _, value in if let port = Int(value) { onPort(port) } }

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Start", action: onStart)
                    .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                    .disabled(!settings.isEnabled || !usable || running)
                Button("Stop", action: onStop)
                    .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                    .disabled(!running)
                Button("Restart", action: onRestart)
                    .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                    .disabled(!settings.isEnabled || !usable)
                Button("Rotate Token", action: onRotateToken)
                    .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                    .disabled(!usable)
            }
            .padding(.horizontal, SettingsMetrics.horizontalPadding)
            .padding(.vertical, SettingsMetrics.rowVerticalPadding + 2)
        }
        .onAppear {
            bindText = settings.bindAddress
            portText = String(settings.normalizedPort)
        }
        .onChange(of: settings.bindAddress) { _, value in bindText = value }
        .onChange(of: settings.port) { _, value in portText = String(value) }
    }

    private var installButtons: some View {
        HStack(spacing: 8) {
            if installed {
                Button("Uninstall", action: onUninstall)
                    .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                    .disabled(isWorking)
            }
            Button(primaryTitle, action: onInstall)
                .buttonStyle(KajiButtonStyle(.primary, size: .small))
                .disabled(isWorking)
        }
    }

    private var installed: Bool {
        if case .missing = installState { return false }
        return true
    }

    private var usable: Bool {
        if case .installed = installState { return true }
        return false
    }

    private var running: Bool {
        if case .running = status { return true }
        return false
    }

    private var primaryTitle: String {
        if isWorking { return "Working" }
        if case .needsRepair = installState { return "Update" }
        return installed ? "Repair" : "Install"
    }

    private var statusText: String {
        if case let .needsRepair(reason) = installState { return reason }
        if !installed { return "Install Claude Code Router for local routing." }
        return status.label
    }

    private var statusColor: Color {
        if case .failed = status { return KajiTheme.diffRemoveFg }
        if case .needsRepair = installState { return KajiTheme.diffRemoveFg }
        return usable ? KajiTheme.fgMuted : KajiTheme.fgDim
    }

    private var footer: String {
        "Claude Code uses \(settings.anthropicBaseURL). Codex uses \(settings.openAIBaseURL)."
    }
}
