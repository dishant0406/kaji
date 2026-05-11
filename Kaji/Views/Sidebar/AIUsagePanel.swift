import SwiftUI

struct AIUsagePanel: View {
    let snapshots: [AIProviderUsageSnapshot]
    let isRefreshing: Bool
    let lastRefreshDate: Date?
    let onRefresh: () -> Void

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if snapshots.isEmpty {
                Text(isRefreshing ? "Refreshing usage data..." : "No usage data yet.")
                    .kajiFont(size: 12)
                    .foregroundStyle(KajiTheme.fgDim)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(snapshots) { snapshot in
                        AIProviderUsageView(snapshot: snapshot)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(KajiTheme.tertiaryBackground, in: RoundedRectangle(cornerRadius: KajiShape.panelRadius))
    }

    private var header: some View {
        HStack(spacing: 6) {
            KajiIcon(systemName: "sparkles", size: 12)
                .foregroundStyle(KajiTheme.fgMuted)
            Text("AI Usage")
                .kajiFont(size: 12, weight: .semibold)
                .foregroundStyle(KajiTheme.fgMuted)
            Spacer()
            Button(action: onRefresh) {
                Group {
                    if isRefreshing {
                        KajiSpinner(size: 12, lineWidth: 1.5)
                    } else {
                        KajiIcon(systemName: "arrow.clockwise", size: 11)
                    }
                }
                .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .foregroundStyle(KajiTheme.fgMuted)
            .disabled(isRefreshing)
            .help("Refresh usage")

            if let lastRefreshDate {
                Text(Self.relativeFormatter.localizedString(for: lastRefreshDate, relativeTo: Date()))
                    .kajiFont(size: 11)
                    .foregroundStyle(KajiTheme.fgDim)
            }
        }
    }
}

private struct AIProviderUsageView: View {
    let snapshot: AIProviderUsageSnapshot

    @AppStorage(AIUsageSettingsStore.sidebarPreviewProviderIDKey) private var pinnedRawValue = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ProviderIconView(iconName: snapshot.providerIconName, size: 14, style: .monochrome(KajiTheme.fg))
                Text(snapshot.providerName)
                    .kajiFont(size: 12, weight: .medium)
                    .foregroundStyle(KajiTheme.fg)
                Spacer(minLength: 4)
            }

            switch snapshot.state {
            case .available:
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(snapshot.rows) { row in
                        AIUsageMetricRowView(
                            row: row,
                            fetchedAt: snapshot.fetchedAt,
                            providerID: snapshot.providerID,
                            isPinned: AIUsageSettingsStore.isSidebarPinned(
                                providerID: snapshot.providerID,
                                rowLabel: row.label,
                                pinnedRawValue: pinnedRawValue
                            )
                        )
                    }
                }
            case let .unavailable(message),
                 let .error(message):
                Text(message)
                    .kajiFont(size: 12)
                    .foregroundStyle(KajiTheme.fgDim)
            }
        }
    }
}
