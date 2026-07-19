import SwiftUI

struct MeetingTranscriptionDiarizationRow: View {
    @ObservedObject var controller: MeetingTranscriptionSettingsController

    var body: some View {
        if controller.showsDiarization {
            SettingsDetailToggleRow(
                label: "Speaker diarization",
                detail: "Identify speakers when the selected model supports it.",
                isOn: Binding(
                    get: { controller.settingsStore.settings.sttDiarizationEnabled },
                    set: { controller.setDiarization($0) }
                )
            )
        }
    }
}
