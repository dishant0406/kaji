import SwiftUI

struct ShortcutBadge: View {
    let label: String
    var compact: Bool = false

    var body: some View {
        Text(label)
            .droidFont(size: compact ? 9 : 10, weight: .medium, design: .monospaced)
            .foregroundStyle(DroidTheme.fg)
            .padding(.horizontal, compact ? 4 : 6)
            .padding(.vertical, compact ? 1 : 2)
            .background(DroidTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: DroidShape.badgeRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DroidShape.badgeRadius)
                    .strokeBorder(DroidTheme.border, lineWidth: 1)
            )
            .accessibilityLabel("Keyboard shortcut: \(label)")
    }
}
