import SwiftUI

struct SettingsSidebarButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Capsule()
                    .fill(KajiTheme.accent)
                    .frame(width: 3, height: 16)
                    .opacity(isSelected ? 1 : 0)
                KajiIcon(systemName: icon, size: 12)
                    .frame(width: 14)
                Text(title)
                    .kajiFont(size: 12, weight: .medium)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? KajiTheme.fg : (hovered ? KajiTheme.fg : KajiTheme.fgMuted))
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
            .overlay(
                RoundedRectangle(cornerRadius: KajiShape.tileRadius)
                    .stroke(rowBorder, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .kajiPointer()
        .animation(KajiMotion.preferred(KajiMotion.hover, reduceMotion: reduceMotion), value: hovered)
        .animation(KajiMotion.preferred(KajiMotion.fast, reduceMotion: reduceMotion), value: isSelected)
    }

    private var rowBackground: Color {
        if isSelected { return KajiTheme.accentSoft.opacity(0.72) }
        if hovered { return KajiTheme.hover.opacity(0.72) }
        return .clear
    }

    private var rowBorder: Color {
        if isSelected { return KajiTheme.accent.opacity(0.32) }
        if hovered { return KajiTheme.border.opacity(0.5) }
        return .clear
    }
}
