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
                        .kajiFont(size: SettingsMetrics.labelFontSize, weight: .medium)
                        .foregroundStyle(KajiTheme.fg)
                    Text(summary)
                        .kajiFont(size: SettingsMetrics.footnoteFontSize)
                        .foregroundStyle(KajiTheme.fgDim)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                    if let status {
                        Text(status)
                            .kajiFont(size: SettingsMetrics.footnoteFontSize)
                            .foregroundStyle(KajiTheme.fgDim)
                            .kajiChangeFeedback(status == "Sent" ? KajiMotion.successFeedback : KajiMotion.invalidFeedback, value: status)
                    }

                    Button {
                        runTest()
                    } label: {
                        HStack(spacing: 6) {
                            if isTesting {
                                KajiSpinner(size: 10, lineWidth: 1.4)
                            }
                            Text(isTesting ? "Sending" : "Test")
                        }
                    }
                    .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                .disabled(isTesting)

                Button("Edit", action: onEdit)
                    .buttonStyle(KajiButtonStyle(.ghost, size: .small))

                    Button("Delete") {
                        onDelete()
                    }
                        .buttonStyle(KajiButtonStyle(.ghost, size: .small))
                        .kajiChangeFeedback(KajiMotion.attentionFeedback, value: destination.id)

                KajiSwitch(
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
