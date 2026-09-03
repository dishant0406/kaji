import SwiftUI

struct MeetingTranscriptionCredentialEditor: View {
    @ObservedObject var controller: MeetingTranscriptionSettingsController

    var body: some View {
        SettingsRow("Profile name") {
            KajiInput(
                placeholder: "Work account",
                text: $controller.credentialName,
                width: 320
            )
        }
        SettingsRow("API key") {
            KajiInput(
                placeholder: "Stored in Keychain",
                text: $controller.credentialSecret,
                width: 320,
                secure: true
            )
        }
        if let error = controller.credentialError {
            SettingsRow("") {
                Text(error)
                    .kajiFont(size: SettingsMetrics.footnoteFontSize)
                    .foregroundStyle(KajiTheme.diffRemoveFg)
                    .frame(width: 320, alignment: .leading)
            }
        }
        SettingsRow("") {
            HStack(spacing: 8) {
                if case .editing = controller.credentialEditorState {
                    Button("Delete", action: controller.deleteCredential)
                        .buttonStyle(KajiButtonStyle(.danger, size: .small))
                }
                Spacer(minLength: 0)
                Button("Cancel", action: controller.cancelCredentialEditor)
                    .buttonStyle(KajiButtonStyle(.ghost, size: .small))
                Button("Save", action: controller.saveCredential)
                    .buttonStyle(KajiButtonStyle(.primary, size: .small))
                    .disabled(!canSave)
            }
            .frame(width: 320)
        }
    }

    private var canSave: Bool {
        !controller.credentialName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !controller.credentialSecret.isEmpty
    }
}
