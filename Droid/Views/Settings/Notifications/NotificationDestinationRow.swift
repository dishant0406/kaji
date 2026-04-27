import SwiftUI

struct NotificationDestinationRow: View {
    let destination: NotificationDeliveryDestination
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onTest: () async -> String?
    @State private var isTesting = false
    @State private var status: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(destination.name)
                        .droidFont(size: SettingsMetrics.labelFontSize, weight: .medium)
                        .foregroundStyle(DroidTheme.fg)
                    Text(summary)
                        .droidFont(size: SettingsMetrics.footnoteFontSize)
                        .foregroundStyle(DroidTheme.fgDim)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if let status {
                    Text(status)
                        .droidFont(size: SettingsMetrics.footnoteFontSize)
                        .foregroundStyle(DroidTheme.fgDim)
                }

                Button("Test") {
                    runTest()
                }
                .buttonStyle(DroidButtonStyle(.secondary, size: .small))
                .disabled(isTesting)

                Button("Edit", action: onEdit)
                    .buttonStyle(DroidButtonStyle(.ghost, size: .small))

                Button("Delete", action: onDelete)
                    .buttonStyle(DroidButtonStyle(.ghost, size: .small))

                DroidSwitch(
                    isOn: Binding(
                        get: { destination.isEnabled },
                        set: { value in onToggle(value) }
                    )
                )
            }
            .padding(.horizontal, SettingsMetrics.horizontalPadding)
            .padding(.vertical, SettingsMetrics.rowVerticalPadding + 2)
        }
    }

    private var summary: String {
        let host = URL(string: destination.endpointURL)?.host ?? destination.endpointURL
        return "\(destination.type.rawValue) • \(host)"
    }

    private func runTest() {
        status = nil
        isTesting = true
        Task {
            let result = await onTest()
            await MainActor.run {
                isTesting = false
                status = result ?? "Sent"
            }
        }
    }
}
