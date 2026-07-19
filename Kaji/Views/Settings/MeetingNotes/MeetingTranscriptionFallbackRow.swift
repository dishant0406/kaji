import SwiftUI

struct MeetingTranscriptionFallbackRow: View { @ObservedObject var controller: MeetingTranscriptionSettingsController

    var body: some View {
        if controller.settingsStore.settings.sttMode != .localChunked {
            SettingsDetailToggleRow(
                label: "Local fallback",
                detail: "Use the configured local model after a disclosed cloud transcription failure.",
                isOn: Binding(
                    get: { controller.settingsStore.settings.localFallbackEnabled },
                    set: { controller.setLocalFallback($0) }
                )
            )
        }
    }
}
