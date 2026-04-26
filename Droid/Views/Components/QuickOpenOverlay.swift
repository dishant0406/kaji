import SwiftUI

struct QuickOpenOverlay: View {
    let projectPath: String
    let onSelect: (String) -> Void
    let onDismiss: () -> Void

    var body: some View {
        PaletteOverlay<FileSearchResult>(
            placeholder: "Type a file name or path",
            emptyLabel: "No files found",
            noMatchLabel: "No matching files",
            search: { query in
                await FileSearchService.search(query: query, in: projectPath)
            },
            onSelect: { result in onSelect(result.absolutePath) },
            onDismiss: onDismiss,
            row: { result, isHighlighted in
                AnyView(FileResultRow(result: result, isHighlighted: isHighlighted))
            }
        )
    }
}

private struct FileResultRow: View {
    let result: FileSearchResult
    let isHighlighted: Bool
    @State private var hovered = false

    private var directoryPath: String {
        let url = URL(fileURLWithPath: result.relativePath)
        let directory = url.deletingLastPathComponent().path
        return directory == "." ? projectRootLabel : directory
    }

    private var projectRootLabel: String {
        "/"
    }

    private var rowBackground: Color {
        if isHighlighted {
            return DroidTheme.secondaryBackground
        }
        if hovered {
            return DroidTheme.chrome.opacity(0.72)
        }
        return .clear
    }

    private var fileIcon: String {
        let ext = URL(fileURLWithPath: result.absolutePath).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js",
             "jsx",
             "mjs": return "j.square"
        case "ts",
             "tsx",
             "mts": return "t.square"
        case "py": return "p.square"
        case "json": return "curlybraces"
        case "html",
             "htm": return "chevron.left.forwardslash.chevron.right"
        case "css",
             "scss": return "paintbrush"
        case "md",
             "markdown": return "doc.richtext"
        case "yaml",
             "yml",
             "toml": return "gearshape"
        case "sh",
             "bash",
             "zsh": return "terminal"
        default: return "doc.text"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            DroidIcon(systemName: fileIcon, size: 12)
                .foregroundStyle(isHighlighted ? DroidTheme.fg : DroidTheme.fgMuted)
                .frame(width: 16)
            Text(result.fileName)
                .droidFont(size: 13, weight: .medium)
                .foregroundStyle(DroidTheme.fg)
                .lineLimit(1)
            Spacer(minLength: 12)
            Text(directoryPath)
                .droidFont(size: 11, design: .monospaced)
                .foregroundStyle(isHighlighted ? DroidTheme.fgMuted : DroidTheme.fgDim)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: DroidShape.panelRadius)
                .fill(rowBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DroidShape.panelRadius)
                .stroke(isHighlighted ? DroidTheme.borderStrong : .clear, lineWidth: 1)
        )
        .onHover { isHovered in
            hovered = isHovered
        }
    }
}
