import SwiftUI

struct TopBarSearchButton: View {
    let title: String
    let shortcut: String
    let enabled: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                KajiIcon(systemName: "magnifyingglass", size: 14)
                    .foregroundStyle(iconColor)

                Text(title)
                    .kajiFont(size: 13)
                    .foregroundStyle(enabled ? KajiTheme.fgMuted : KajiTheme.fgDim)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ShortcutBadge(label: shortcut, compact: true)
                    .opacity(enabled ? 1 : 0.45)
            }
            .padding(.horizontal, 14)
            .frame(width: 340, height: 30)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: KajiShape.tileRadius))
            .overlay {
                RoundedRectangle(cornerRadius: KajiShape.tileRadius)
                    .strokeBorder(KajiTheme.border.opacity(hovered && enabled ? 1 : 0.65), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovered = $0 }
        .kajiPointer()
        .help("Quick Open (\(shortcut))")
        .accessibilityLabel("Quick Open")
    }

    private var background: Color {
        guard enabled else { return KajiTheme.secondaryBackground.opacity(0.75) }
        return hovered ? KajiTheme.surface : KajiTheme.secondaryBackground
    }

    private var iconColor: Color {
        enabled && hovered ? KajiTheme.fg : KajiTheme.fgDim
    }
}
