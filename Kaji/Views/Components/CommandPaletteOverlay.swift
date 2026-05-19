import SwiftUI

struct CommandPaletteOverlay: View {
    let onSelect: (AppCommand) -> Void
    let onDismiss: () -> Void

    var body: some View {
        PaletteOverlay<AppCommand>(
            placeholder: "Type a command",
            emptyLabel: "No commands available",
            noMatchLabel: "No matching commands",
            search: { query in
                AppCommandRegistry.search(query)
            },
            onSelect: onSelect,
            onDismiss: onDismiss,
            row: { command, isHighlighted in
                AnyView(CommandPaletteRow(command: command, isHighlighted: isHighlighted))
            }
        )
    }
}

private struct CommandPaletteRow: View {
    let command: AppCommand
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 10) {
            KajiIcon(systemName: icon, size: 12)
                .foregroundStyle(isHighlighted ? KajiTheme.fg : KajiTheme.fgMuted)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(command.title)
                    .kajiFont(size: 13, weight: .medium)
                    .foregroundStyle(KajiTheme.fg)
                    .lineLimit(1)
                Text(command.category)
                    .kajiFont(size: 10)
                    .foregroundStyle(KajiTheme.fgDim)
            }
            Spacer(minLength: 12)
            if let shortcut = command.shortcut {
                Text(shortcut.displayString)
                    .kajiFont(size: 11, design: .monospaced)
                    .foregroundStyle(isHighlighted ? KajiTheme.fgMuted : KajiTheme.fgDim)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(KajiTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 5))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: KajiShape.panelRadius)
                .fill(isHighlighted ? KajiTheme.secondaryBackground : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: KajiShape.panelRadius)
                .stroke(isHighlighted ? KajiTheme.borderStrong : .clear, lineWidth: 1)
        )
    }

    private var icon: String {
        switch command.category {
        case "Editor": "text.cursor"
        case "Navigation": "arrow.triangle.branch"
        case "Tabs": "rectangle.on.rectangle"
        case "Panes": "rectangle.split.2x1"
        case "Terminal": "terminal"
        case "Project Navigation": "folder"
        default: "command"
        }
    }
}
