import SwiftUI

struct AskPaletteList: View {
    let entries: [AskPaletteEntry]
    let highlightedIndex: Int?
    let emptyLabel: String
    var isLoading = false
    let onSelect: (AskPaletteEntry) -> Void

    var body: some View {
        Group {
            if entries.isEmpty {
                VStack {
                    Spacer()
                    if isLoading {
                        KajiSpinner(size: 14)
                    }
                    Text(emptyLabel)
                        .kajiFont(size: 12)
                        .foregroundStyle(KajiTheme.fgDim)
                    Spacer()
                }
            } else {
                VirtualizedList(items: entries, rowHeight: 52, highlightedIndex: highlightedIndex) { index, entry in
                    AskPaletteRow(entry: entry, isHighlighted: index == highlightedIndex)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(entry) }
                        .kajiPointer()
                }
                .padding(.vertical, 8)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

private struct AskPaletteRow: View {
    let entry: AskPaletteEntry
    let isHighlighted: Bool
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            KajiIcon(systemName: iconName, size: 12)
                .foregroundStyle(isHighlighted ? KajiTheme.fg : KajiTheme.fgMuted)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .kajiFont(size: 13, weight: .medium)
                    .foregroundStyle(KajiTheme.fg)
                    .lineLimit(1)
                Text(entry.detail)
                    .kajiFont(size: 11)
                    .foregroundStyle(isHighlighted ? KajiTheme.fgMuted : KajiTheme.fgDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            if let annotation = entry.annotation {
                Text(annotation)
                    .kajiFont(size: 11, design: .monospaced)
                    .foregroundStyle(isHighlighted ? KajiTheme.fgMuted : KajiTheme.fgDim)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: KajiShape.panelRadius)
                .fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: KajiShape.panelRadius)
                .stroke(isHighlighted ? KajiTheme.borderStrong : .clear, lineWidth: 1)
        )
        .onHover { hovered = $0 }
    }

    private var background: Color {
        if isHighlighted {
            return KajiTheme.secondaryBackground
        }
        if hovered {
            return KajiTheme.chrome.opacity(0.72)
        }
        return .clear
    }

    private var iconName: String {
        switch entry.action {
        case .command:
            "command"
        case .project:
            "folder"
        case .worktree:
            "arrow.triangle.branch"
        case .provider:
            "sparkles"
        case .sessionMode:
            "square.stack"
        case .session:
            "terminal"
        case .bookmarkSession:
            "bookmark"
        case .bookmarkLookupLoading:
            "arrow.triangle.2.circlepath"
        case .bookmarkFolder:
            "folder"
        case .createBookmarkFolder:
            "folder.badge.plus"
        case .savedBookmark:
            "bookmark"
        case .bookmarkFolderFilter:
            "folder"
        case .saveSelectedBookmarks:
            "checkmark.circle"
        case .history:
            "clock.arrow.circlepath"
        case .skill:
            "wand.and.stars"
        case .taskRecipe,
             .openTaskForm,
             .editTaskRecipe,
             .deleteTaskRecipe:
            "checklist"
        case .mention:
            "at"
        case .directory:
            "folder"
        case .diffFile,
             .openDiffSummary:
            "file.diff"
        case .gitCommand:
            "terminal"
        case .gitBranch,
             .gitSwitchBranch,
             .gitCheckoutBranch:
            "arrow.triangle.branch"
        case .gitCommitDiff:
            "clock"
        case .gitPreviewPlaceholder:
            "terminal"
        case .attach:
            "paperclip"
        case .runScript,
             .openScriptForm,
             .deleteScript:
            "chevron.left.forwardslash.chevron.right"
        case .toggleSleepPrevention:
            "moon.zzz"
        case .toggleBatteryLidCloseSleepPrevention:
            "laptopcomputer"
        case .launchProvider:
            "play"
        case .submit:
            "arrow.up.right"
        }
    }
}
