import SwiftUI

struct MeetingTranscriptionSettingsSection: View {
    @StateObject private var controller = MeetingTranscriptionSettingsController()

    var body: some View {
        SettingsSection("Transcription", footer: controller.destinationSummary) {
            MeetingTranscriptionProviderRow(controller: controller)
            MeetingTranscriptionEndpointRows(controller: controller)
            MeetingTranscriptionCredentialRows(controller: controller)
            MeetingTranscriptionModeRow(controller: controller)
            MeetingTranscriptionModelRow(controller: controller)
            MeetingTranscriptionCapabilityRows(controller: controller)
            MeetingTranscriptionLocalModelRow(controller: controller)
        }
        MeetingTranscriptionAdvancedSection(controller: controller)
            .onAppear { controller.start() }
    }
}
