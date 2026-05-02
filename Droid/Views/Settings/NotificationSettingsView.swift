import AppKit
import SwiftUI

struct NotificationSettingsView: View {
    private enum EditorState {
        case destination(NotificationDeliveryDestination?)
        case route(NotificationRoutingRule?)
    }

    @AppStorage("droid.notifications.sound") private var sound = NotificationSound.funk.rawValue
    @AppStorage("droid.notifications.toastEnabled") private var toastEnabled = true
    @AppStorage("droid.notifications.toastPosition") private var toastPosition = ToastPosition.topCenter.rawValue
    @State private var integrations = NotificationIntegrationStore.shared
    @State private var editorState: EditorState?

    var body: some View {
        Group {
            switch editorState {
            case let .destination(existing):
                NotificationDestinationModal(
                    existing: existing,
                    bearerToken: existing.map { integrations.bearerToken(for: $0.id) } ?? "",
                    onCancel: { editorState = nil },
                    onSave: { destination, bearerToken in
                        integrations.upsertDestination(destination, bearerToken: bearerToken)
                        editorState = nil
                    }
                )
            case let .route(existing):
                NotificationRouteModal(
                    existing: existing,
                    destinations: integrations.destinations,
                    onCancel: { editorState = nil },
                    onSave: { route in
                        integrations.upsertRoute(route)
                        editorState = nil
                    }
                )
            case nil:
                settingsList
            }
        }
    }

    private var settingsList: some View {
        ScrollView {
            SettingsContainer {
                SettingsSection("Delivery") {
                    SettingsToggleRow(label: "Toast", isOn: $toastEnabled)
                }

                SettingsSection("Sound") {
                    SettingsPickerRow<NotificationSound>(
                        label: "Sound",
                        selection: $sound,
                        width: 160
                    )
                    .onChange(of: sound) { _, newValue in
                        previewSound(newValue)
                    }
                }

                SettingsSection("Toast") {
                    SettingsPickerRow<ToastPosition>(
                        label: "Position",
                        selection: $toastPosition,
                        width: 160
                    )
                }

                NotificationDestinationsSection(
                    onAdd: { editorState = .destination(nil) },
                    onEdit: { destination in
                        editorState = .destination(destination)
                    }
                )

                NotificationRoutesSection(
                    onAdd: { editorState = .route(nil) },
                    onEdit: { route in
                        editorState = .route(route)
                    }
                )

                SettingsSection("AI Providers", showsDivider: false) {
                    ForEach(AIProviderRegistry.shared.providers, id: \.id) { provider in
                        ProviderToggleRow(provider: provider)
                    }
                }
            }
        }
    }

    private func previewSound(_ value: String) {
        guard let sound = NotificationSound(rawValue: value), sound != .none else { return }
        NSSound(named: .init(sound.rawValue))?.play()
    }
}

private struct ProviderToggleRow: View {
    let provider: AIProviderIntegration
    @State private var enabled: Bool
    @State private var installed: Bool
    @State private var installing = false
    @State private var installMessage: String?
    @State private var refreshed = false

    init(provider: AIProviderIntegration) {
        self.provider = provider
        let isInstalled = provider.isToolInstalled()
        _installed = State(initialValue: isInstalled)
        _enabled = State(initialValue: isInstalled && provider.isEnabled)
    }

    var body: some View {
        HStack(spacing: 10) {
            ProviderIconView(iconName: provider.iconName, size: 12, style: .monochrome(.secondary))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName)
                    .droidFont(size: SettingsMetrics.labelFontSize)
                    .foregroundStyle(DroidTheme.fg)
                Text(installMessage ?? (installed ? "Installed" : "CLI not installed"))
                    .droidFont(size: SettingsMetrics.footnoteFontSize)
                    .foregroundStyle(installed ? DroidTheme.fgDim : DroidTheme.diffRemoveFg)
            }
            Spacer()
            if installed, enabled {
                Button {
                    AIProviderRegistry.shared.forceInstall(provider)
                    withAnimation { refreshed = true }
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { refreshed = false }
                    }
                } label: {
                    if refreshed {
                        Label {
                            Text("Done")
                        } icon: {
                            DroidIcon(systemName: "checkmark", size: 10)
                        }
                    } else {
                        Text("Refresh")
                    }
                }
                .buttonStyle(DroidButtonStyle(.secondary, size: .small))
                .disabled(refreshed)
            }
            if !installed {
                Button(installing ? "Installing" : "Install") {
                    installProvider()
                }
                .buttonStyle(DroidButtonStyle(.secondary, size: .small))
                .disabled(installing)
            }
            DroidSwitch(isOn: $enabled)
                .disabled(!installed || installing)
                .onChange(of: enabled) { _, newValue in
                    guard installed else {
                        enabled = false
                        provider.isEnabled = false
                        return
                    }
                    provider.isEnabled = newValue
                    AIProviderRegistry.shared.installAll()
                }
        }
        .padding(.horizontal, SettingsMetrics.horizontalPadding)
        .padding(.vertical, SettingsMetrics.rowVerticalPadding)
        .onAppear(perform: refreshInstallState)
    }

    private func refreshInstallState() {
        installed = provider.isToolInstalled()
        if !installed {
            enabled = false
            provider.isEnabled = false
        }
    }

    private func installProvider() {
        guard let command = AIProviderInstaller.command(for: provider) else {
            installMessage = "Install is not supported"
            return
        }
        installing = true
        installMessage = "Installing..."
        Task { @MainActor in
            let result = await AIProviderInstaller.install(command)
            installed = provider.isToolInstalled()
            installing = false
            switch result {
            case .success where installed:
                enabled = true
                provider.isEnabled = true
                AIProviderRegistry.shared.installAll()
                installMessage = "Installed"
            case .success:
                installMessage = "Install finished, but CLI was not found"
            case let .failure(error):
                enabled = false
                provider.isEnabled = false
                installMessage = error.localizedDescription
            }
        }
    }
}
