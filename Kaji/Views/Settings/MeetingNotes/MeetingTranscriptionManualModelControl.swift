import SwiftUI

struct MeetingTranscriptionManualModelControl: View {
    @ObservedObject var controller: MeetingTranscriptionSettingsController

    var body: some View {
        HStack(spacing: 8) {
            KajiInput(
                placeholder: "Model or deployment ID",
                text: $controller.manualModelID,
                width: 220,
                monospaced: true
            )
            Button("Use") { controller.useManualModel() }
                .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                .disabled(controller.manualModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if controller.selectedEndpoint?.discovery.kind != .manual {
                Button("Cancel") { controller.closeManualModelEntry() }
                    .buttonStyle(KajiButtonStyle(.ghost, size: .small))
            }
        }
        .frame(width: 320, alignment: .trailing)
    }
}
