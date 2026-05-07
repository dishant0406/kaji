import SwiftUI

struct ExtensionsSettingsView: View {
    @State private var store = DroidCodeGraphStore.shared
    @State private var isInstalling = false

    var body: some View {
        ScrollView {
            SettingsContainer {
                SettingsSection(
                    "Extensions",
                    footer: "DroidCodeGraph runs Graphify from ~/.droid/extensions. Instructions stay outside the project.",
                    showsDivider: false
                ) {
                    DroidCodeGraphExtensionRow(
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
    }

    private func install() {
        guard !isInstalling else { return }
        isInstalling = true
        Task { @MainActor in
            await DroidCodeGraphInstaller().install(store: store)
            isInstalling = false
        }
    }
}

private struct DroidCodeGraphExtensionRow: View {
    let store: DroidCodeGraphStore
    let isInstalling: Bool
    let onInstall: () -> Void
    let onToggle: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                DroidIcon(systemName: "point.3.connected.trianglepath.dotted", size: 16)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text("DroidCodeGraph")
                        .droidFont(size: SettingsMetrics.labelFontSize, weight: .medium)
                        .foregroundStyle(DroidTheme.fg)
                    Text(statusText)
                        .droidFont(size: SettingsMetrics.footnoteFontSize)
                        .foregroundStyle(statusColor)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                if store.isInstalled {
                    Button("Repair") {
                        onInstall()
                    }
                    .buttonStyle(DroidButtonStyle(.secondary, size: .small))
                    .disabled(isInstalling)
                } else {
                    Button(isInstalling ? "Installing" : "Install") {
                        onInstall()
                    }
                    .buttonStyle(DroidButtonStyle(.secondary, size: .small))
                    .disabled(isInstalling)
                }

                DroidSwitch(isOn: Binding(
                    get: { store.state.isEnabled },
                    set: { value in onToggle(value) }
                ))
                .disabled(!store.isInstalled || isInstalling)
            }
            .padding(.horizontal, SettingsMetrics.horizontalPadding)
            .padding(.vertical, SettingsMetrics.rowVerticalPadding + 4)

            SettingsGraphPathRow(label: "Runtime", path: DroidCodeGraphDirectory.root.path)
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
        if store.state.phase == .failed { return DroidTheme.diffRemoveFg }
        return store.isInstalled ? DroidTheme.fgMuted : DroidTheme.fgDim
    }
}

private struct SettingsGraphPathRow: View {
    let label: String
    let path: String

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .droidFont(size: SettingsMetrics.footnoteFontSize)
                .foregroundStyle(DroidTheme.fgDim)
                .frame(width: 58, alignment: .leading)
            Text(path)
                .droidFont(size: SettingsMetrics.footnoteFontSize, design: .monospaced)
                .foregroundStyle(DroidTheme.fgMuted)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, SettingsMetrics.horizontalPadding)
        .padding(.bottom, SettingsMetrics.rowVerticalPadding + 4)
    }
}
