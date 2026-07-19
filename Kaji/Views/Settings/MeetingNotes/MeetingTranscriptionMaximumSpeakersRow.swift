import SwiftUI

struct MeetingTranscriptionMaximumSpeakersRow: View {
    @ObservedObject var controller: MeetingTranscriptionSettingsController

    var body: some View {
        if controller.showsMaximumSpeakers {
            SettingsRow("Maximum speakers") {
                MeetingNotesIntegerControl(
                    value: controller.settingsStore.settings.sttMaximumSpeakers ?? 2,
                    range: 1 ... 32,
                    suffix: "",
                    onChange: controller.setMaximumSpeakers
                )
            }
        }
    }
}
