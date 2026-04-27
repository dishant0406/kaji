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
    @State private var refreshed = false

    init(provider: AIProviderIntegration) {
        self.provider = provider
        _enabled = State(initialValue: provider.isEnabled)
    }

    var body: some View {
        HStack {
            ProviderIconView(iconName: provider.iconName, size: 12, style: .monochrome(.secondary))
                .frame(width: 16)
            Text(provider.displayName)
                .droidFont(size: SettingsMetrics.labelFontSize)
                .foregroundStyle(DroidTheme.fg)
            Spacer()
            if enabled {
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
            DroidSwitch(isOn: $enabled)
                .onChange(of: enabled) { _, newValue in
                    provider.isEnabled = newValue
                    AIProviderRegistry.shared.installAll()
                }
        }
        .padding(.horizontal, SettingsMetrics.horizontalPadding)
        .padding(.vertical, SettingsMetrics.rowVerticalPadding)
    }
}
