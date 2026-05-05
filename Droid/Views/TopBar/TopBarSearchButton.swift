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
                DroidIcon(systemName: "magnifyingglass", size: 14)
                    .foregroundStyle(iconColor)

                Text(title)
                    .droidFont(size: 13)
                    .foregroundStyle(enabled ? DroidTheme.fgMuted : DroidTheme.fgDim)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ShortcutBadge(label: shortcut, compact: true)
                    .opacity(enabled ? 1 : 0.45)
            }
            .padding(.horizontal, 14)
            .frame(width: 340, height: 30)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: DroidShape.tileRadius))
            .overlay {
                RoundedRectangle(cornerRadius: DroidShape.tileRadius)
                    .strokeBorder(DroidTheme.border.opacity(hovered && enabled ? 1 : 0.65), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovered = $0 }
        .help("Quick Open (\(shortcut))")
        .accessibilityLabel("Quick Open")
    }

    private var background: Color {
        guard enabled else { return DroidTheme.secondaryBackground.opacity(0.75) }
        return hovered ? DroidTheme.surface : DroidTheme.secondaryBackground
    }

    private var iconColor: Color {
        enabled && hovered ? DroidTheme.fg : DroidTheme.fgDim
    }
}
