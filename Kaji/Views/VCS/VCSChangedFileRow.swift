import SwiftUI

struct VCSChangedFileRow: View {
    let file: GitStatusFile
    let statusText: String
    let expanded: Bool
    let showsInlineDisclosure: Bool
    let stats: VCSTabState.FileStats
    let isStaged: Bool
    let onPrimaryAction: () -> Void
    let onStage: () -> Void
    let onUnstage: () -> Void
    let onDiscard: () -> Void
    let onOpenInEditor: () -> Void
    let onOpenDiff: () -> Void
    @State private var hovered = false

    private var statusColor: Color {
        switch statusText.first {
        case "A":
            KajiTheme.diffAddFg
        case "D":
            KajiTheme.diffRemoveFg
        case "M",
             "R":
            KajiTheme.accent
        case "U":
            KajiTheme.diffAddFg
        default:
            KajiTheme.fgMuted
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            leadingIcon

            Text(statusText)
                .kajiFont(size: 11, weight: .bold, design: .monospaced)
                .foregroundStyle(statusColor)
                .frame(width: 14)

            FileDiffIcon()
                .stroke(statusColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .frame(width: 11, height: 11)

            Text(file.path)
                .kajiFont(size: 12, weight: .medium)
                .foregroundStyle(KajiTheme.fg)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            if hovered {
                actionButtons
            }

            statsView
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(hovered ? KajiTheme.hover : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .animation(KajiMotion.fast, value: expanded)
        .animation(KajiMotion.hover, value: hovered)
        .kajiChangeFeedback(KajiMotion.selectionFeedback, value: expanded, isEnabled: expanded)
        .onTapGesture(perform: onPrimaryAction)
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if showsInlineDisclosure {
            KajiIcon(systemName: expanded ? "chevron.down" : "chevron.right", size: 10)
                .foregroundStyle(KajiTheme.fgDim)
                .frame(width: 12)
        } else {
            KajiIcon(systemName: "rectangle.split.2x1", size: 10)
                .foregroundStyle(KajiTheme.fgDim)
                .frame(width: 12)
                .help("Open Diff in Main Window")
        }
    }

    @ViewBuilder
    private var statsView: some View {
        if stats.binary {
            Text("Binary")
                .kajiFont(size: 12, weight: .medium)
                .foregroundStyle(KajiTheme.fgMuted)
        } else {
            if let additions = stats.additions {
                Text("+\(additions)")
                    .kajiFont(size: 12, weight: .semibold, design: .monospaced)
                    .foregroundStyle(KajiTheme.diffAddFg)
            }
            if let deletions = stats.deletions {
                Text("-\(deletions)")
                    .kajiFont(size: 12, weight: .semibold, design: .monospaced)
                    .foregroundStyle(KajiTheme.diffRemoveFg)
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 0) {
            IconButton(symbol: "doc.text", size: 11, accessibilityLabel: "Open in Editor", action: onOpenInEditor)
                .help("Open in Editor")
            IconButton(symbol: "rectangle.split.2x1", size: 11, accessibilityLabel: "Open Diff in Main Window", action: onOpenDiff)
                .help("Open Diff in Main Window")
            if isStaged {
                IconButton(symbol: "minus", size: 11, accessibilityLabel: "Unstage", action: onUnstage)
                    .help("Unstage")
            } else {
                IconButton(symbol: "plus", size: 11, accessibilityLabel: "Stage", action: onStage)
                    .help("Stage")
                IconButton(symbol: "arrow.uturn.backward", size: 11, accessibilityLabel: "Discard Changes", action: onDiscard)
                    .help("Discard changes")
            }
        }
    }
}
