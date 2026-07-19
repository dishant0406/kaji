import SwiftUI

struct MeetingTranscriptionLoadedModelControl: View {
    @ObservedObject var controller: MeetingTranscriptionSettingsController

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if controller.displayedModels.isEmpty {
                emptyContent
            } else {
                HStack(spacing: 8) {
                    MeetingTranscriptionModelPicker(controller: controller, width: 240)
                    Button(controller.modelListIsRefreshing ? "Refreshing…" : "Refresh") {
                        controller.refreshModels()
                    }
                    .buttonStyle(KajiButtonStyle(.ghost, size: .small))
                    .disabled(controller.modelListIsRefreshing)
                }
                if controller.modelListIsStale {
                    Text("Using the last successful model list")
                        .kajiFont(size: SettingsMetrics.footnoteFontSize)
                        .foregroundStyle(KajiTheme.diffHunkFg)
                }
                manualAction
            }
        }
        .frame(width: 320, alignment: .trailing)
    }

    private var emptyContent: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 8) {
                Text("No models found")
                    .kajiFont(size: SettingsMetrics.labelFontSize)
                    .foregroundStyle(KajiTheme.fgDim)
                Button("Refresh") { controller.refreshModels() }
                    .buttonStyle(KajiButtonStyle(.secondary, size: .small))
            }
            manualAction
        }
    }

    @ViewBuilder
    private var manualAction: some View {
        if controller.selectedEndpoint?.source == .custom {
            Button("Use model ID…") { controller.openManualModelEntry() }
                .buttonStyle(KajiButtonStyle(.ghost, size: .small))
        }
    }
}
