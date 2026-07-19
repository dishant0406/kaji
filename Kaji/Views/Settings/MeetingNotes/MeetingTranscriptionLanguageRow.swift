import SwiftUI

struct MeetingTranscriptionLanguageRow: View { @ObservedObject var controller: MeetingTranscriptionSettingsController

    var body: some View {
        if controller.showsLanguage {
            SettingsRow("Language") {
                KajiSelect(
                    options: controller.languageOptions,
                    selection: Binding(
                        get: { controller.settingsStore.settings.sttLanguageCodes.first ?? "" },
                        set: { controller.selectLanguage($0) }
                    ),
                    width: 320
                )
                .accessibilityLabel("Transcription language")
            }
        }
    }
}
