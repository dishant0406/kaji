import SwiftUI

struct AIUsageMetricRowView: View {
    let row: AIUsageMetricRow
    let fetchedAt: Date
    let providerID: String
    let isPinned: Bool

    @AppStorage(AIUsageSettingsStore.usageDisplayModeKey) private var usageDisplayModeRaw = AIUsageSettingsStore.defaultUsageDisplayMode
        .rawValue
    @State private var pinHovered = false

    private static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private var usageDisplayMode: AIUsageDisplayMode {
        AIUsageDisplayMode(rawValue: usageDisplayModeRaw) ?? AIUsageSettingsStore.defaultUsageDisplayMode
    }

    private var displayPercent: Double? {
        AIUsageMetricDisplayFormatter.displayPercent(for: row, displayMode: usageDisplayMode)
    }

    private var displayDetail: String? {
        AIUsageMetricDisplayFormatter.displayDetail(for: row, displayMode: usageDisplayMode)
    }

    private var paceResult: AIUsagePaceResult? {
        AIUsageMetricDisplayFormatter.paceResult(for: row, fetchedAt: fetchedAt)
    }

    private var paceDetailText: String? {
        AIUsageMetricDisplayFormatter.paceDetailText(
            for: row,
            fetchedAt: fetchedAt,
            displayMode: usageDisplayMode
        )
    }

    private var canPin: Bool { row.percent != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(row.label)
                    .kajiFont(size: 12)
                    .foregroundStyle(KajiTheme.fgMuted)

                if paceDetailText != nil {
                    Circle()
                        .fill(paceIndicatorColor)
                        .frame(width: 6, height: 6)
                }

                if canPin {
                    Button(action: togglePin) {
                        KajiIcon(systemName: isPinned ? "pin.fill" : "pin", size: 10)
                            .foregroundStyle(isPinned ? KajiTheme.accent : (pinHovered ? KajiTheme.fg : KajiTheme.fgMuted))
                            .rotationEffect(.degrees(45))
                            .frame(width: 14, height: 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { pinHovered = $0 }
                    .help(isPinned ? "Unpin from top bar" : "Show this usage in the top bar")
                }

                Spacer()

                if let percent = displayPercent {
                    Text("\(Int(percent.rounded()))%")
                        .kajiFont(size: 12, weight: .medium)
                        .foregroundStyle(KajiTheme.fg)
                }

                if let detail = displayDetail {
                    Text(detail)
                        .kajiFont(size: 11)
                        .foregroundStyle(KajiTheme.fgDim)
                }
            }

            if let percent = displayPercent {
                KajiLinearProgressBar(value: percent, total: 100, height: 5)
            }

            if let resetDate = row.resetDate {
                HStack(spacing: 6) {
                    Text("Resets \(Self.resetFormatter.string(from: resetDate))")
                        .kajiFont(size: 11)
                        .foregroundStyle(KajiTheme.fgDim)

                    Spacer(minLength: 0)

                    if let paceDetailText {
                        Text(paceDetailText)
                            .kajiFont(size: 11)
                            .foregroundStyle(KajiTheme.fgDim)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private var paceIndicatorColor: Color {
        guard let paceResult else { return .clear }
        switch paceResult.status {
        case .ahead:
            return .green
        case .onTrack:
            return .yellow
        case .behind:
            return .red
        }
    }

    private func togglePin() {
        if isPinned {
            AIUsageSettingsStore.setSidebarPreviewPin(nil)
            return
        }

        AIUsageSettingsStore.setSidebarPreviewPin(
            AISidebarPreviewPin(providerID: providerID, rowLabel: row.label)
        )
    }
}
