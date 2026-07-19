import SwiftUI

struct MeetingTranscriptionAdvancedSection: View {
    @ObservedObject var controller: MeetingTranscriptionSettingsController

    var body: some View {
        SettingsSection("Advanced transcription") {
            Button(controller.showsAdvanced ? "Hide advanced settings" : "Show advanced settings") {
                controller.showsAdvanced.toggle()
            }
            .buttonStyle(.plain)
            .kajiPointer()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SettingsMetrics.horizontalPadding)
            .padding(.vertical, SettingsMetrics.rowVerticalPadding + 4)
            if controller.showsAdvanced {
                MeetingTranscriptionKeytermsRow(controller: controller)
                MeetingTranscriptionLanguageDetectionRow(controller: controller)
                MeetingTranscriptionFallbackRow(controller: controller)
            }
        }
    }
}
