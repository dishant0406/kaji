import SwiftUI

struct AgentCommandCenterSectionHeader: View {
    let section: AgentCommandCenterSection

    var body: some View {
        HStack(spacing: 8) {
            Text(section.title)
                .kajiFont(size: 12, weight: .semibold)
                .foregroundStyle(KajiTheme.fg)
                .lineLimit(1)
            Text(statusText)
                .kajiFont(size: 11)
                .foregroundStyle(statusColor)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(section.detail)
                .kajiFont(size: 11)
                .foregroundStyle(KajiTheme.fgDim)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 14)
        .padding(.top, 9)
        .padding(.bottom, 4)
    }

    private var statusText: String {
        switch section.status {
        case .needsAttention:
            "Needs attention"
        case .notice:
            "Notice"
        case .running:
            "Running"
        case .completed:
            "Completed"
        case .failed:
            "Failed"
        }
    }

    private var statusColor: Color {
        switch section.status {
        case .needsAttention:
            KajiTheme.diffHunkFg
        case .notice:
            KajiTheme.fgMuted
        case .running:
            KajiTheme.accent
        case .completed:
            KajiTheme.fgDim
        case .failed:
            KajiTheme.diffRemoveFg
        }
    }
}
