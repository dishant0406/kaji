import SwiftUI

struct MeetingTranscriptionModelPicker: View {
    @ObservedObject var controller: MeetingTranscriptionSettingsController
    let width: CGFloat

    var body: some View {
        KajiSelect(
            options: controller.modelOptions,
            selection: Binding(
                get: { controller.settingsStore.settings.sttModelID },
                set: { controller.selectModel($0) }
            ),
            placeholder: "Choose model",
            width: width
        )
        .accessibilityLabel("Transcription model")
    }
}
