import SwiftUI

struct UpdateBadge: View {
    let version: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                KajiIcon(systemName: "arrow.down.circle.fill", size: 9)
                Text("Update \(version)")
                    .kajiFont(size: 10, weight: .semibold, design: .monospaced)
                    .lineLimit(1)
            }
            .foregroundStyle(hovered ? KajiTheme.accent : KajiTheme.fgMuted)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: KajiShape.badgeRadius)
                    .fill(KajiTheme.secondaryBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: KajiShape.badgeRadius)
                    .stroke(KajiTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .kajiHoverEffect(isActive: hovered, scale: 1.02)
        .kajiChangeFeedback(KajiMotion.attentionFeedback, value: version)
        .accessibilityLabel("Update available: version \(version)")
        .accessibilityHint("Activates to check for updates")
    }
}
