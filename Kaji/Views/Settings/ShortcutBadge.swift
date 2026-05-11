import SwiftUI

struct ShortcutBadge: View {
    let label: String
    var compact: Bool = false

    var body: some View {
        Text(label)
            .kajiFont(size: compact ? 9 : 10, weight: .medium, design: .monospaced)
            .foregroundStyle(KajiTheme.fg)
            .padding(.horizontal, compact ? 4 : 6)
            .padding(.vertical, compact ? 1 : 2)
            .background(KajiTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: KajiShape.badgeRadius))
            .overlay(
                RoundedRectangle(cornerRadius: KajiShape.badgeRadius)
                    .strokeBorder(KajiTheme.border, lineWidth: 1)
            )
            .accessibilityLabel("Keyboard shortcut: \(label)")
    }
}
