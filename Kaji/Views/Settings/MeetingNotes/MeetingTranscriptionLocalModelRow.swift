import SwiftUI

struct MeetingTranscriptionLocalModelRow: View {
    @ObservedObject var controller: MeetingTranscriptionSettingsController

    var body: some View {
        if controller.showsLocalModelDownload,
           let model = SpeechModelRegistryStore.shared.models.first(where: {
               $0.id == controller.settingsStore.settings.sttModelID
           }),
           !model.cacheState.isReady
        {
            SettingsRow("Local model") {
                Button("Open Speech to Text settings") {
                    NotificationCenter.default.post(name: .openSpeechToTextSettings, object: nil)
                }
                .buttonStyle(KajiButtonStyle(.secondary, size: .small))
            }
        }
    }
}
