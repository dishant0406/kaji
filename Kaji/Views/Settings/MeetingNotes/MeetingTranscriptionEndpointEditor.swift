import SwiftUI

struct MeetingTranscriptionEndpointEditor: View {
    @ObservedObject var controller: MeetingTranscriptionSettingsController

    var body: some View {
        SettingsRow("Name") {
            KajiInput(
                placeholder: "Corporate gateway",
                text: $controller.endpointName,
                width: 320
            )
        }
        if controller.selectedEndpoint?.variant != .assemblyAIStreamingV3 {
            SettingsRow("REST base URL") {
                KajiInput(
                    placeholder: "https://speech.example.com/v1",
                    text: $controller.restBaseURL,
                    width: 320,
                    monospaced: true
                )
            }
        }
        SettingsRow("WebSocket base URL") {
            KajiInput(
                placeholder: "wss://speech.example.com/v1",
                text: $controller.webSocketBaseURL,
                width: 320,
                monospaced: true
            )
        }
        if let error = controller.endpointError {
            SettingsRow("") {
                Text(error)
                    .kajiFont(size: SettingsMetrics.footnoteFontSize)
                    .foregroundStyle(KajiTheme.diffRemoveFg)
                    .frame(width: 320, alignment: .leading)
            }
        }
        SettingsRow("") {
            HStack(spacing: 8) {
                if case .editing = controller.endpointEditorState {
                    Button("Delete", action: controller.deleteEndpoint)
                        .buttonStyle(KajiButtonStyle(.danger, size: .small))
                }
                Spacer(minLength: 0)
                Button("Cancel", action: controller.cancelEndpointEditor)
                    .buttonStyle(KajiButtonStyle(.ghost, size: .small))
                Button("Save", action: controller.saveEndpoint)
                    .buttonStyle(KajiButtonStyle(.primary, size: .small))
                    .disabled(!canSave)
            }
            .frame(width: 320)
        }
    }

    private var canSave: Bool {
        let hasName = !controller.endpointName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasWebSocket = !controller.webSocketBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let needsREST = controller.selectedEndpoint?.variant != .assemblyAIStreamingV3
        let hasREST = !controller.restBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasName && hasWebSocket && (!needsREST || hasREST)
    }
}
