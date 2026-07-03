import SwiftUI

struct ExtensionsSettingsView: View {
    @State private var store = KajiCodeGraphStore.shared
    @State private var isInstalling = false
    @State private var isInstallingBrowserMCP = false
    @State private var isInstallingCodeGraphMCP = false
    @State private var browserMCPAgents = [String]()
    @State private var codeGraphMCPAgents = [String]()
    @State private var browserMCPMessage: String?
    @State private var codeGraphMCPMessage: String?
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
                    footer: [
                        "KajiCodeGraph runs Graphify from ~/.kaji/extensions.",
                        "Agent context is user-managed through copied prompts and optional MCP tools.",
                    ].joined(separator: " "),
                    showsDivider: false
                ) {
                    KajiCodeGraphExtensionRow(
                        store: store,
                        isInstalling: isInstalling,
                        onInstall: install,
                        onToggle: { store.setEnabled($0) }
                    )
                    KajiCodeGraphPromptCopyRow(
                        onCopyCodeGraph: copyCodeGraphDocument,
                        onCopyAgentsReference: copyAgentsReference,
                        onCopyClaudeReference: copyClaudeReference
                    )
                    KajiCodeGraphMCPInstallRow(
                        installedAgents: codeGraphMCPAgents,
                        isInstalling: isInstallingCodeGraphMCP,
                        message: codeGraphMCPMessage,
                        onInstall: installCodeGraphMCP,
                        onUninstall: uninstallCodeGraphMCP
                    )
                }
            }
        }
        .onAppear {
            store.refreshFromDisk()
            refreshBrowserMCPState()
            refreshCodeGraphMCPState()
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

    private func copyCodeGraphDocument() {
        KajiCodeGraphPromptClipboard.copyCodeGraphDocument()
        codeGraphMCPMessage = "Copied CODE_GRAPH.md content."
    }

    private func copyAgentsReference() {
        KajiCodeGraphPromptClipboard.copyAgentsReference()
        codeGraphMCPMessage = "Copied AGENTS.md reference."
    }

    private func copyClaudeReference() {
        KajiCodeGraphPromptClipboard.copyClaudeReference()
        codeGraphMCPMessage = "Copied CLAUDE.md reference."
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

    private func installCodeGraphMCP() {
        guard !isInstallingCodeGraphMCP else { return }
        isInstallingCodeGraphMCP = true
        Task { @MainActor in
            let outcomes = KajiCodeGraphMCPInstallService.installAll()
            codeGraphMCPAgents = KajiCodeGraphMCPInstallService.installedAgentIDs()
            let failed = outcomes.filter { !$0.installed }
            codeGraphMCPMessage = failed.isEmpty ? "Installed read-only CodeGraph MCP tools." : failed
                .map { "\($0.agentID): \($0.detail)" }.joined(separator: ", ")
            isInstallingCodeGraphMCP = false
        }
    }

    private func uninstallCodeGraphMCP() {
        guard !isInstallingCodeGraphMCP else { return }
        isInstallingCodeGraphMCP = true
        Task { @MainActor in
            let outcomes = KajiCodeGraphMCPInstallService.uninstallAll()
            codeGraphMCPAgents = KajiCodeGraphMCPInstallService.installedAgentIDs()
            let failed = outcomes.filter(\.installed)
            codeGraphMCPMessage = failed.isEmpty ? "Uninstalled from agent MCP configs." : failed
                .map { "\($0.agentID): \($0.detail)" }.joined(separator: ", ")
            isInstallingCodeGraphMCP = false
        }
    }

    private func refreshBrowserMCPState() {
        browserMCPAgents = KajiBrowserMCPInstallService.installedAgentIDs()
    }

    private func refreshCodeGraphMCPState() {
        codeGraphMCPAgents = KajiCodeGraphMCPInstallService.installedAgentIDs()
    }
}
