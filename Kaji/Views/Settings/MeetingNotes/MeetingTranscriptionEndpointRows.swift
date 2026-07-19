import SwiftUI

struct MeetingTranscriptionEndpointRows: View {
    @ObservedObject var controller: MeetingTranscriptionSettingsController

    var body: AnyView {
        guard controller.showsEndpoint else { return AnyView(EmptyView()) }
        guard controller.endpointEditorState == .hidden else {
            return AnyView(MeetingTranscriptionEndpointEditor(controller: controller))
        }
        return AnyView(endpointRow)
    }

    private var endpointRow: some View {
        SettingsRow("Endpoint") {
            HStack(spacing: 8) {
                KajiSelect(
                    options: controller.endpointOptions,
                    selection: endpointSelection,
                    width: 230
                )
                .accessibilityLabel("Transcription endpoint")
                endpointAction
            }
        }
    }

    private var endpointSelection: Binding<String> {
        Binding(
            get: { controller.settingsStore.settings.sttEndpointProfileID?.uuidString ?? "" },
            set: { value in
                guard let id = UUID(uuidString: value) else { return }
                controller.selectEndpoint(id)
            }
        )
    }

    @ViewBuilder
    private var endpointAction: some View {
        if controller.selectedEndpoint?.source == .custom {
            Button("Edit…") { controller.beginEditEndpoint() }
                .buttonStyle(KajiButtonStyle(.secondary, size: .small))
        } else {
            Button("Add…") { controller.beginCreateEndpoint() }
                .buttonStyle(KajiButtonStyle(.secondary, size: .small))
        }
    }
}
