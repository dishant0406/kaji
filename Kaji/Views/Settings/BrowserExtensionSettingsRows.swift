import SwiftUI

struct BrowserExtensionRow: View {
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            KajiIcon(systemName: "globe", size: 16)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text("Kaji Browser")
                    .kajiFont(size: SettingsMetrics.labelFontSize, weight: .medium)
                    .foregroundStyle(KajiTheme.fg)
                Text(statusText)
                    .kajiFont(size: SettingsMetrics.footnoteFontSize)
                    .foregroundStyle(KajiTheme.fgMuted)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            KajiSwitch(isOn: $isEnabled)
        }
        .padding(.horizontal, SettingsMetrics.horizontalPadding)
        .padding(.vertical, SettingsMetrics.rowVerticalPadding + 4)
    }

    private var statusText: String {
        isEnabled ? "Enabled for the native side panel" : "Disabled, browser UI hidden"
    }
}

struct BrowserMCPInstallRow: View {
    let installedAgents: [String]
    let isInstalling: Bool
    let message: String?
    let onInstall: () -> Void
    let onUninstall: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            KajiIcon(systemName: "puzzlepiece.extension", size: 16)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text("Kaji Browser MCP")
                    .kajiFont(size: SettingsMetrics.labelFontSize, weight: .medium)
                    .foregroundStyle(KajiTheme.fg)
                Text(statusText)
                    .kajiFont(size: SettingsMetrics.footnoteFontSize)
                    .foregroundStyle(KajiTheme.fgMuted)
                    .lineLimit(2)
                if let message {
                    Text(message)
                        .kajiFont(size: SettingsMetrics.footnoteFontSize)
                        .foregroundStyle(KajiTheme.fgDim)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if !installedAgents.isEmpty {
                    Button("Uninstall") {
                        onUninstall()
                    }
                    .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                    .disabled(isInstalling)
                }

                Button {
                    onInstall()
                } label: {
                    HStack(spacing: 6) {
                        if isInstalling {
                            KajiSpinner(size: 10, lineWidth: 1.4)
                        }
                        Text(buttonTitle)
                    }
                }
                .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                .disabled(isInstalling)
            }
        }
        .padding(.horizontal, SettingsMetrics.horizontalPadding)
        .padding(.vertical, SettingsMetrics.rowVerticalPadding + 4)
    }

    private var buttonTitle: String {
        if isInstalling {
            return "Installing"
        }
        return installedAgents.isEmpty ? "Install" : "Repair"
    }

    private var statusText: String {
        if installedAgents.isEmpty {
            return "Manual MCP install, not injected into agents"
        }
        return "Installed for " + installedAgents.map(displayName).joined(separator: ", ")
    }

    private func displayName(_ id: String) -> String {
        switch id {
        case "claude": "Claude"
        case "codex": "Codex"
        case "opencode": "OpenCode"
        case "pi": "Pi"
        default: id
        }
    }
}
