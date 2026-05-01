import SwiftUI

struct AgentCommandCenterSectionHeader: View {
    let section: AgentCommandCenterSection

    var body: some View {
        HStack(spacing: 8) {
            Text(section.title)
                .droidFont(size: 12, weight: .semibold)
                .foregroundStyle(DroidTheme.fg)
                .lineLimit(1)
            Text(statusText)
                .droidFont(size: 11)
                .foregroundStyle(statusColor)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(section.detail)
                .droidFont(size: 11)
                .foregroundStyle(DroidTheme.fgDim)
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
            DroidTheme.diffHunkFg
        case .notice:
            DroidTheme.fgMuted
        case .running:
            DroidTheme.accent
        case .completed:
            DroidTheme.fgDim
        case .failed:
            DroidTheme.diffRemoveFg
        }
    }
}
