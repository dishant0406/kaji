import SwiftUI

struct ExtensionsSettingsView: View {
    @State private var store = KajiCodeGraphStore.shared
    @State private var isInstalling = false
    @AppStorage(BrowserExtensionPreferences.enabledKey) private var browserEnabled = false
    @AppStorage(BrowserExtensionPreferences.unsafeToolsEnabledKey) private var unsafeBrowserToolsEnabled = false

    var body: some View {
        ScrollView {
            SettingsContainer {
                SettingsSection(
                    "Browser",
                    footer: "Enable Kaji Browser to show the browser side panel and expose kaji-browser tools to coding agents."
                ) {
                    BrowserExtensionRow(isEnabled: $browserEnabled)
                    BrowserUnsafeToolsRow(
                        isEnabled: $unsafeBrowserToolsEnabled,
                        isBrowserEnabled: browserEnabled
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
        }
        .onChange(of: browserEnabled) { _, enabled in
            BrowserExtensionPreferences.isEnabled = enabled
            _ = CodingAgentShimInstaller.install(installBrowserMCP: enabled)
            if enabled {
                CodingAgentBrowserEnvironment.writeInstalledConfigs(homeDirectory: NSHomeDirectory())
            } else {
                CodingAgentBrowserEnvironment.removeConfigs(homeDirectory: NSHomeDirectory())
                KajiBrowserSessionEnvironmentStore.remove()
            }
        }
        .onChange(of: unsafeBrowserToolsEnabled) { _, enabled in
            BrowserExtensionPreferences.allowsUnsafeTools = enabled
            guard browserEnabled else { return }
            CodingAgentBrowserEnvironment.writeInstalledConfigs(homeDirectory: NSHomeDirectory())
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
                    Button("Repair") {
                        onInstall()
                    }
                    .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                    .disabled(isInstalling)
                } else {
                    Button(isInstalling ? "Installing" : "Install") {
                        onInstall()
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
