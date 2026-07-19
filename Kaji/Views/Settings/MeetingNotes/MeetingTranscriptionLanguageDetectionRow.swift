import SwiftUI

struct MeetingTranscriptionLanguageDetectionRow: View {
    @ObservedObject var controller: MeetingTranscriptionSettingsController

    var body: some View {
        if controller.selectedModel?.capabilities.languageIdentification.availability != .unsupported {
            SettingsDetailToggleRow(
                label: "Automatic language detection",
                detail: "Allow the provider to identify language when no explicit language is selected.",
                isOn: Binding(
                    get: { controller.settingsStore.settings.sttProviderOptions.automaticLanguageDetection },
                    set: { controller.setAutomaticLanguageDetection($0) }
                )
            )
        }
    }
}
