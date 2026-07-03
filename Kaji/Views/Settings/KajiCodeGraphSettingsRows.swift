import SwiftUI

struct KajiCodeGraphExtensionRow: View {
    let store: KajiCodeGraphStore
    let isInstalling: Bool
    let onInstall: () -> Void
    let onToggle: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                KajiIcon(systemName: "point.3.connected.trianglepath.dotted", size: 16)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text("KajiCodeGraph")
                        .kajiFont(size: SettingsMetrics.labelFontSize, weight: .medium)
                        .foregroundStyle(KajiTheme.fg)
                    Text(statusText)
                        .kajiFont(size: SettingsMetrics.footnoteFontSize)
                        .foregroundStyle(statusColor)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Button {
                    onInstall()
                } label: {
                    installButtonLabel(title: store.isInstalled ? "Repair" : "Install")
                }
                .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                .disabled(isInstalling)
                KajiSwitch(isOn: Binding(get: { store.state.isEnabled }, set: { value in onToggle(value) }))
                    .disabled(!store.isInstalled || isInstalling)
            }
            .padding(.horizontal, SettingsMetrics.horizontalPadding)
            .padding(.vertical, SettingsMetrics.rowVerticalPadding + 4)
            .kajiChangeFeedback(KajiMotion.successFeedback, value: store.isInstalled, isEnabled: store.isInstalled)
            .kajiChangeFeedback(KajiMotion.invalidFeedback, value: store.state.phase == .failed, isEnabled: store.state.phase == .failed)
            SettingsGraphPathRow(label: "Runtime", path: KajiCodeGraphDirectory.root.path)
            SettingsGraphPathRow(label: "Graphify", path: store.state.graphifyCommit ?? "Not installed")
        }
    }

    private var statusText: String {
        if isInstalling { return "Installing Graphify runtime..." }
        if let message = store.state.message, store.state.phase == .failed { return message }
        if store.isReady { return "Enabled for manual graph generation" }
        if store.isInstalled { return "Disabled, installed" }
        return "Not installed"
    }

    private var statusColor: Color {
        if store.state.phase == .failed { return KajiTheme.diffRemoveFg }
        return store.isInstalled ? KajiTheme.fgMuted : KajiTheme.fgDim
    }

    private func installButtonLabel(title: String) -> some View {
        HStack(spacing: 6) {
            if isInstalling { KajiSpinner(size: 10, lineWidth: 1.4) }
            Text(isInstalling ? "Installing" : title)
        }
    }
}

struct KajiCodeGraphPromptCopyRow: View {
    let onCopyCodeGraph: () -> Void
    let onCopyAgentsReference: () -> Void
    let onCopyClaudeReference: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            KajiIcon(systemName: "doc.on.doc", size: 16)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text("CodeGraph prompt snippets")
                    .kajiFont(size: SettingsMetrics.labelFontSize, weight: .medium)
                    .foregroundStyle(KajiTheme.fg)
                Text("Copy user-managed instructions into CODE_GRAPH.md, AGENTS.md, or CLAUDE.md.")
                    .kajiFont(size: SettingsMetrics.footnoteFontSize)
                    .foregroundStyle(KajiTheme.fgMuted)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                copyButton("CODE_GRAPH.md", action: onCopyCodeGraph)
                copyButton("AGENTS ref", action: onCopyAgentsReference)
                copyButton("CLAUDE ref", action: onCopyClaudeReference)
            }
        }
        .padding(.horizontal, SettingsMetrics.horizontalPadding)
        .padding(.vertical, SettingsMetrics.rowVerticalPadding + 4)
    }

    private func copyButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(KajiButtonStyle(.secondary, size: .small))
    }
}

struct KajiCodeGraphMCPInstallRow: View {
    let installedAgents: [String]
    let isInstalling: Bool
    let message: String?
    let onInstall: () -> Void
    let onUninstall: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            KajiIcon(systemName: "point.3.filled.connected.trianglepath.dotted", size: 16)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text("Kaji CodeGraph MCP")
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
                    Button("Uninstall", action: onUninstall)
                        .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                        .disabled(isInstalling)
                }
                Button {
                    onInstall()
                } label: {
                    HStack(spacing: 6) {
                        if isInstalling { KajiSpinner(size: 10, lineWidth: 1.4) }
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
        if isInstalling { return "Installing" }
        return installedAgents.isEmpty ? "Install" : "Repair"
    }

    private var statusText: String {
        if installedAgents.isEmpty { return "Manual MCP install for read-only graph tools" }
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

private struct SettingsGraphPathRow: View {
    let label: String
    let path: String

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .kajiFont(size: SettingsMetrics.footnoteFontSize)
                .foregroundStyle(KajiTheme.fgDim)
                .frame(width: 58, alignment: .leading)
            Text(path)
                .kajiFont(size: SettingsMetrics.footnoteFontSize, design: .monospaced)
                .foregroundStyle(KajiTheme.fgMuted)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, SettingsMetrics.horizontalPadding)
        .padding(.bottom, SettingsMetrics.rowVerticalPadding + 4)
    }
}
