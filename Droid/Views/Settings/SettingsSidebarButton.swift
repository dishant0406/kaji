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
                    .fill(DroidTheme.accent)
                    .frame(width: 3, height: 16)
                    .opacity(isSelected ? 1 : 0)
                DroidIcon(systemName: icon, size: 12)
                    .frame(width: 14)
                Text(title)
                    .droidFont(size: 12, weight: .medium)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? DroidTheme.fg : (hovered ? DroidTheme.fg : DroidTheme.fgMuted))
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: DroidShape.tileRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DroidShape.tileRadius)
                    .stroke(rowBorder, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: DroidShape.tileRadius))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .droidPointer()
        .animation(DroidMotion.preferred(DroidMotion.hover, reduceMotion: reduceMotion), value: hovered)
        .animation(DroidMotion.preferred(DroidMotion.fast, reduceMotion: reduceMotion), value: isSelected)
    }

    private var rowBackground: Color {
        if isSelected { return DroidTheme.accentSoft.opacity(0.72) }
        if hovered { return DroidTheme.hover.opacity(0.72) }
        return .clear
    }

    private var rowBorder: Color {
        if isSelected { return DroidTheme.accent.opacity(0.32) }
        if hovered { return DroidTheme.border.opacity(0.5) }
        return .clear
    }
}
