import SwiftUI

struct UserCommandShortcutRow: View {
    let shortcut: UserCommandShortcut
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(shortcut.name)
                        .kajiFont(size: SettingsMetrics.labelFontSize)
                        .foregroundStyle(KajiTheme.fg)
                    ShortcutBadge(label: "::\(shortcut.slug)", compact: true)
                }
                Text(shortcut.command)
                    .kajiFont(size: 11, design: .monospaced)
                    .foregroundStyle(KajiTheme.fgDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            if hovered {
                Button("Edit", action: onEdit)
                    .buttonStyle(KajiButtonStyle(.ghost, size: .small))
                Button("Delete", action: onDelete)
                    .buttonStyle(KajiButtonStyle(.ghost, size: .small))
                    .foregroundStyle(KajiTheme.diffRemoveFg)
            }
        }
        .padding(.horizontal, SettingsMetrics.horizontalPadding)
        .padding(.vertical, SettingsMetrics.rowVerticalPadding)
        .background(hovered ? KajiTheme.surface : .clear)
        .onHover { hovered = $0 }
    }
}
