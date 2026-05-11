import SwiftUI

struct AgentMissionControlSectionHeader: View {
    let section: AgentMissionControlSection

    var body: some View {
        HStack(spacing: 6) {
            Text(section.kind.title)
                .kajiFont(size: 9, weight: .semibold, design: .monospaced)
                .foregroundStyle(KajiTheme.fgDim)
            KajiBadge(text: "\(section.items.count)", variant: badgeVariant)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var badgeVariant: KajiBadgeVariant {
        switch section.kind {
        case .needsAttention:
            .warning
        case .running:
            .accent
        case .failed:
            .danger
        case .completed,
             .notifications:
            .neutral
        }
    }
}
