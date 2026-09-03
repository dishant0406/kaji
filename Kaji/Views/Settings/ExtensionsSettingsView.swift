import SwiftUI

struct ExtensionsSettingsView: View {
    @State private var isInstallingBrowserMCP = false
    @State private var browserMCPAgents = [String]()
    @State private var browserMCPMessage: String?
    @AppStorage(BrowserExtensionPreferences.enabledKey) private var browserEnabled = false
    @AppStorage(KasetMusicPreferences.enabledKey) private var kasetMusicEnabled = false
    @AppStorage(KasetMusicPreferences.showFooterIconKey) private var kasetMusicShowsFooterIcon = true

    var body: some View {
        ScrollView {
            SettingsContainer {
                SettingsSection(
                    "Kaset",
                    footer: "Embeds the Kaset package for YouTube Music and YouTube playback without copying Kaset source into Kaji."
                ) {
                    KasetMusicSettingsRow(
                        isEnabled: $kasetMusicEnabled,
                        showsFooterIcon: $kasetMusicShowsFooterIcon
                    )
                }

                SettingsSection(
                    "Browser",
                    footer: "Enable the native browser side panel. Install the MCP explicitly for agents that should use browser tools.",
                    showsDivider: false
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
            }
        }
        .onAppear {
            refreshBrowserMCPState()
        }
        .onChange(of: browserEnabled) { _, enabled in
            BrowserExtensionPreferences.isEnabled = enabled
            if !enabled {
                KajiBrowserControlBroker.shared.stop()
                KajiBrowserSessionEnvironmentStore.remove()
            }
        }
        .onChange(of: kasetMusicEnabled) { _, enabled in
            KasetMusicPreferences.isEnabled = enabled
            if !enabled {
                NotificationCenter.default.post(name: .closeKasetMusicPanel, object: nil)
                NotificationCenter.default.post(name: .shutdownKasetMusic, object: nil)
            }
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
