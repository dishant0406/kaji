import SwiftUI

struct MeetingTranscriptionRetentionRow: View { @ObservedObject var controller: MeetingTranscriptionSettingsController

    var body: AnyView {
        if controller.showsRetentionPicker {
            return AnyView(pickerRow)
        }
        if let text = controller.retentionText {
            return AnyView(textRow(text))
        }
        return AnyView(EmptyView())
    }

    private var pickerRow: some View {
        SettingsRow("Retention") {
            KajiSelect(
                options: controller.retentionOptions,
                selection: retentionSelection,
                width: 320
            )
            .accessibilityLabel("Transcription retention")
        }
    }

    private func textRow(_ text: String) -> some View {
        SettingsRow("Retention") {
            Text(text)
                .kajiFont(size: SettingsMetrics.labelFontSize)
                .foregroundStyle(KajiTheme.fgMuted)
                .frame(width: 320, alignment: .leading)
        }
    }

    private var retentionSelection: Binding<String> {
        Binding(
            get: { controller.settingsStore.settings.sttRetention.rawValue },
            set: { value in
                guard let retention = MeetingTranscriptionDataRetentionClass(rawValue: value) else { return }
                controller.selectRetention(retention)
            }
        )
    }
}
