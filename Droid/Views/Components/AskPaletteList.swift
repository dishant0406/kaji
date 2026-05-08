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
                        DroidSpinner(size: 14)
                    }
                    Text(emptyLabel)
                        .droidFont(size: 12)
                        .foregroundStyle(DroidTheme.fgDim)
                    Spacer()
                }
            } else {
                VirtualizedList(items: entries, rowHeight: 52, highlightedIndex: highlightedIndex) { index, entry in
                    AskPaletteRow(entry: entry, isHighlighted: index == highlightedIndex)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(entry) }
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
            DroidIcon(systemName: iconName, size: 12)
                .foregroundStyle(isHighlighted ? DroidTheme.fg : DroidTheme.fgMuted)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .droidFont(size: 13, weight: .medium)
                    .foregroundStyle(DroidTheme.fg)
                    .lineLimit(1)
                Text(entry.detail)
                    .droidFont(size: 11)
                    .foregroundStyle(isHighlighted ? DroidTheme.fgMuted : DroidTheme.fgDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            if let annotation = entry.annotation {
                Text(annotation)
                    .droidFont(size: 11, design: .monospaced)
                    .foregroundStyle(isHighlighted ? DroidTheme.fgMuted : DroidTheme.fgDim)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: DroidShape.panelRadius)
                .fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DroidShape.panelRadius)
                .stroke(isHighlighted ? DroidTheme.borderStrong : .clear, lineWidth: 1)
        )
        .onHover { hovered = $0 }
    }

    private var background: Color {
        if isHighlighted {
            return DroidTheme.secondaryBackground
        }
        if hovered {
            return DroidTheme.chrome.opacity(0.72)
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
