import SwiftUI

struct MeetingTranscriptionCredentialRows: View {
    @ObservedObject var controller: MeetingTranscriptionSettingsController

    var body: some View {
        if controller.showsCredential {
            switch controller.credentialEditorState {
            case .hidden:
                credentialRow
            case .creating,
                 .editing:
                MeetingTranscriptionCredentialEditor(controller: controller)
            }
        }
    }

    private var credentialRow: some View {
        SettingsRow("API key") {
            HStack(spacing: 8) {
                if controller.credentialProfiles.isEmpty {
                    Button("Add API key…") { controller.beginCreateCredential() }
                        .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                } else {
                    KajiSelect(
                        options: controller.credentialOptions,
                        selection: Binding(
                            get: { controller.settingsStore.settings.sttCredentialProfileID?.uuidString ?? "" },
                            set: { controller.selectCredential(UUID(uuidString: $0)) }
                        ),
                        width: 230
                    )
                    .accessibilityLabel("Transcription API key")
                    if controller.settingsStore.settings.sttCredentialProfileID == nil {
                        Button("Add…") { controller.beginCreateCredential() }
                            .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                    } else {
                        Button("Manage") { controller.beginEditCredential() }
                            .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                    }
                }
            }
        }
    }
}
