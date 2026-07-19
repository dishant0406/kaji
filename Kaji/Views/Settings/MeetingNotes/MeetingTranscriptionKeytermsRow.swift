import SwiftUI

struct MeetingTranscriptionKeytermsRow: View { @ObservedObject var controller: MeetingTranscriptionSettingsController

    var body: some View {
        if controller.selectedModel?.capabilities.keyterms.availability != .unsupported {
            VStack(alignment: .leading, spacing: 6) {
                KajiTextArea(
                    placeholder: "One key term per line",
                    text: Binding(
                        get: { controller.settingsStore.settings.sttKeyterms.joined(separator: "\n") },
                        set: { controller.setKeyterms($0) }
                    ),
                    minHeight: 70,
                    maxHeight: 130
                )
                .padding(.horizontal, SettingsMetrics.horizontalPadding)
                Text("\(controller.settingsStore.settings.sttKeyterms.count) / 100")
                    .kajiFont(size: 10, design: .monospaced)
                    .foregroundStyle(KajiTheme.fgDim)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, SettingsMetrics.horizontalPadding)
            }
        }
    }
}
