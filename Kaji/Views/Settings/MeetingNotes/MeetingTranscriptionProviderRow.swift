import SwiftUI

struct MeetingTranscriptionProviderRow: View { @ObservedObject var controller: MeetingTranscriptionSettingsController

    var body: some View {
        SettingsRow("Provider") {
            KajiSelect(
                options: controller.providerOptions,
                selection: providerSelection,
                width: 320
            )
            .accessibilityLabel("Transcription provider")
        }
    }

    private var providerSelection: Binding<String> {
        Binding(
            get: { controller.settingsStore.settings.sttProviderID },
            set: { controller.selectProvider($0) }
        )
    }
}
