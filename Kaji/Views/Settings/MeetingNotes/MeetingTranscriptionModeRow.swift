import SwiftUI

struct MeetingTranscriptionModeRow: View { @ObservedObject var controller: MeetingTranscriptionSettingsController

    var body: AnyView {
        guard controller.showsMode else { return AnyView(EmptyView()) }
        return AnyView(SettingsRow("Mode") {
            KajiSelect(
                options: controller.modeOptions,
                selection: modeSelection,
                width: 320
            )
            .accessibilityLabel("Transcription mode")
        })
    }

    private var modeSelection: Binding<String> {
        Binding(
            get: { controller.settingsStore.settings.sttMode.rawValue },
            set: { value in
                guard let mode = MeetingTranscriptionMode(rawValue: value) else { return }
                controller.selectMode(mode)
            }
        )
    }
}
