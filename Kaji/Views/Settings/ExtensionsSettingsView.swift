import SwiftUI

struct ExtensionsSettingsView: View {
    @State private var store = KajiCodeGraphStore.shared
    @State private var isInstalling = false
    @State private var isInstallingBrowserMCP = false
    @State private var browserMCPAgents = [String]()
    @State private var browserMCPMessage: String?
    @AppStorage(BrowserExtensionPreferences.enabledKey) private var browserEnabled = false

    var body: some View {
        ScrollView {
            SettingsContainer {
                SettingsSection(
                    "Browser",
                    footer: "Enable the native browser side panel. Install the MCP explicitly for agents that should use browser tools."
                ) {
                    BrowserExtensionRow(isEnabled: $browserEnabled)
                    BrowserMCPInstallRow(
                        installedAgents: browserMCPAgents,
                        isInstalling: isInstallingBrowserMCP,
                        message: browserMCPMessage,
                        onInstall: installBrowserMCP,
                        onUninstall: uninstallBrowserMCP
                    )
                }

                SettingsSection(
                    "Extensions",
                    footer: "KajiCodeGraph runs Graphify from ~/.kaji/extensions. Instructions stay outside the project.",
                    showsDivider: false
                ) {
                    KajiCodeGraphExtensionRow(
                        store: store,
                        isInstalling: isInstalling,
                        onInstall: install,
                        onToggle: { store.setEnabled($0) }
                    )
                }
            }
        }
        .onAppear {
            store.refreshFromDisk()
            refreshBrowserMCPState()
        }
        .onChange(of: browserEnabled) { _, enabled in
            BrowserExtensionPreferences.isEnabled = enabled
            if !enabled {
                KajiBrowserControlBroker.shared.stop()
                KajiBrowserSessionEnvironmentStore.remove()
            }
        }
    }

    private func install() {
        guard !isInstalling else { return }
        isInstalling = true
        Task { @MainActor in
            await KajiCodeGraphInstaller().install(store: store)
            isInstalling = false
        }
    }

    private func installBrowserMCP() {
        guard !isInstallingBrowserMCP else { return }
        isInstallingBrowserMCP = true
        Task { @MainActor in
            let outcomes = KajiBrowserMCPInstallService.installAll()
            browserMCPAgents = KajiBrowserMCPInstallService.installedAgentIDs()
            let failed = outcomes.filter { !$0.installed }
            browserMCPMessage = failed.isEmpty ? "Installed. Agents will show tools only when Kaji Browser is reachable." : failed
                .map { "\($0.agentID): \($0.detail)" }.joined(separator: ", ")
            isInstallingBrowserMCP = false
        }
    }

    private func uninstallBrowserMCP() {
        guard !isInstallingBrowserMCP else { return }
        isInstallingBrowserMCP = true
        Task { @MainActor in
            let outcomes = KajiBrowserMCPInstallService.uninstallAll()
            browserMCPAgents = KajiBrowserMCPInstallService.installedAgentIDs()
            let failed = outcomes.filter(\.installed)
            browserMCPMessage = failed.isEmpty ? "Uninstalled from agent MCP configs." : failed
                .map { "\($0.agentID): \($0.detail)" }.joined(separator: ", ")
            isInstallingBrowserMCP = false
        }
    }

    private func refreshBrowserMCPState() {
        browserMCPAgents = KajiBrowserMCPInstallService.installedAgentIDs()
    }
}

private struct KajiCodeGraphExtensionRow: View {
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

                if store.isInstalled {
                    Button {
                        onInstall()
                    } label: {
                        installButtonLabel(title: "Repair")
                    }
                    .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                    .disabled(isInstalling)
                } else {
                    Button {
                        onInstall()
                    } label: {
                        installButtonLabel(title: "Install")
                    }
                    .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                    .disabled(isInstalling)
                }

                KajiSwitch(isOn: Binding(
                    get: { store.state.isEnabled },
                    set: { value in onToggle(value) }
                ))
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
        if let message = store.state.message, store.state.phase == .failed {
            return message
        }
        if store.isReady { return "Enabled, installed" }
        if store.isInstalled { return "Disabled, installed" }
        return "Not installed"
    }

    private var statusColor: Color {
        if store.state.phase == .failed { return KajiTheme.diffRemoveFg }
        return store.isInstalled ? KajiTheme.fgMuted : KajiTheme.fgDim
    }

    private func installButtonLabel(title: String) -> some View {
        HStack(spacing: 6) {
            if isInstalling {
                KajiSpinner(size: 10, lineWidth: 1.4)
            }
            Text(isInstalling ? "Installing" : title)
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
