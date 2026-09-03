import AppKit
import SwiftUI

struct NotificationSettingsView: View {
    private enum EditorState {
        case destination(NotificationDeliveryDestination?)
        case route(NotificationRoutingRule?)
    }

    @AppStorage("kaji.notifications.sound") private var sound = NotificationSound.funk.rawValue
    @AppStorage("kaji.notifications.toastEnabled") private var toastEnabled = true
    @AppStorage("kaji.notifications.toastPosition") private var toastPosition = ToastPosition.topCenter.rawValue
    @State private var integrations = NotificationIntegrationStore.shared
    @State private var editorState: EditorState?

    var body: some View {
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
            }
        }
    }

    private func previewSound(_ value: String) {
        guard let sound = NotificationSound(rawValue: value), sound != .none else { return }
        NSSound(named: .init(sound.rawValue))?.play()
    }
}
