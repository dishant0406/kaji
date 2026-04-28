import SwiftUI

struct ResourceMetricBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .droidFont(size: 10, weight: .medium, design: .monospaced)
            .foregroundStyle(DroidTheme.fgMuted)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(DroidTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: DroidShape.badgeRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DroidShape.badgeRadius)
                    .strokeBorder(DroidTheme.border.opacity(0.8), lineWidth: 1)
            )
    }
}
