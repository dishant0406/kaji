import SwiftUI

struct ResourceMetricBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .kajiFont(size: 10, weight: .medium, design: .monospaced)
            .foregroundStyle(KajiTheme.fgMuted)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(KajiTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: KajiShape.badgeRadius))
            .overlay(
                RoundedRectangle(cornerRadius: KajiShape.badgeRadius)
                    .strokeBorder(KajiTheme.border.opacity(0.8), lineWidth: 1)
            )
    }
}
