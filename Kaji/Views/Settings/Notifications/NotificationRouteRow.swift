import SwiftUI

struct NotificationRouteRow: View {
    let route: NotificationRoutingRule
    let destinationNames: [String]
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(route.name)
                    .kajiFont(size: SettingsMetrics.labelFontSize, weight: .medium)
                    .foregroundStyle(KajiTheme.fg)
                Text(summary)
                    .kajiFont(size: SettingsMetrics.footnoteFontSize)
                    .foregroundStyle(KajiTheme.fgDim)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button("Edit", action: onEdit)
                .buttonStyle(KajiButtonStyle(.ghost, size: .small))

            Button("Delete") {
                onDelete()
            }
                .buttonStyle(KajiButtonStyle(.ghost, size: .small))
                .kajiChangeFeedback(KajiMotion.attentionFeedback, value: route.id)

            KajiSwitch(
                isOn: Binding(
                    get: { route.isEnabled },
                    set: { value in onToggle(value) }
                )
            )
        }
        .padding(.horizontal, SettingsMetrics.horizontalPadding)
        .padding(.vertical, SettingsMetrics.rowVerticalPadding + 2)
    }

    private var summary: String {
        let source = route.source.rawValue
        let event = route.eventKind.rawValue
        let sound = route.sound?.rawValue ?? "App default sound"
        let destinations = destinationNames.isEmpty ? "No destinations" : destinationNames.joined(separator: ", ")
        return "\(source) • \(event) • \(destinations) • \(sound)"
    }
}
