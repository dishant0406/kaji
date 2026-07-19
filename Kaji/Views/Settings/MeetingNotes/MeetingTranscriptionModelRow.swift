import SwiftUI

struct MeetingTranscriptionModelRow: View {
    @ObservedObject var controller: MeetingTranscriptionSettingsController

    var body: some View {
        SettingsRow("Model") {
            if controller.usesManualModelEntry {
                MeetingTranscriptionManualModelControl(controller: controller)
            } else {
                modelControl
            }
        }
    }

    @ViewBuilder
    private var modelControl: some View {
        switch controller.modelDisplayState {
        case .local:
            MeetingTranscriptionModelPicker(controller: controller, width: 320)
        case .credentialRequired:
            Text("Add an API key above to load models.")
                .kajiFont(size: SettingsMetrics.labelFontSize)
                .foregroundStyle(KajiTheme.fgDim)
                .frame(width: 320, alignment: .leading)
        case .loading:
            Text("Loading models…")
                .kajiFont(size: SettingsMetrics.labelFontSize)
                .foregroundStyle(KajiTheme.fgDim)
                .frame(width: 320, alignment: .leading)
        case .loaded:
            MeetingTranscriptionLoadedModelControl(controller: controller)
        case .failed:
            MeetingTranscriptionFailedModelControl(controller: controller)
        case .manual:
            MeetingTranscriptionManualModelControl(controller: controller)
        }
    }
}
