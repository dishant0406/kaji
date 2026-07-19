import SwiftUI

struct MeetingTranscriptionFailedModelControl: View {
    @ObservedObject var controller: MeetingTranscriptionSettingsController

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 8) {
                Text(controller.modelFailureMessage)
                    .kajiFont(size: SettingsMetrics.footnoteFontSize)
                    .foregroundStyle(KajiTheme.diffRemoveFg)
                Button("Retry") { controller.refreshModels() }
                    .buttonStyle(KajiButtonStyle(.secondary, size: .small))
            }
            if controller.selectedEndpoint?.source == .custom {
                Button("Use model ID…") { controller.openManualModelEntry() }
                    .buttonStyle(KajiButtonStyle(.ghost, size: .small))
            }
        }
        .frame(width: 320, alignment: .trailing)
    }
}
