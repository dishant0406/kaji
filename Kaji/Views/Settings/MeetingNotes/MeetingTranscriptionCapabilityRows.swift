import SwiftUI

struct MeetingTranscriptionCapabilityRows: View {
    @ObservedObject var controller: MeetingTranscriptionSettingsController

    var body: some View {
        if controller.selectedModelMetadata != nil {
            MeetingTranscriptionLanguageRow(controller: controller)
            MeetingTranscriptionDiarizationRow(controller: controller)
            MeetingTranscriptionMaximumSpeakersRow(controller: controller)
            MeetingTranscriptionRetentionRow(controller: controller)
            MeetingTranscriptionAttestationRow(controller: controller)
        }
    }
}
