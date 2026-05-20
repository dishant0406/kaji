import AppKit
import SwiftUI

struct AllChangesDiffBody: View {
    @Bindable var state: DiffViewerTabState
    let onCommentRequest: (DiffCommentAnchor, CGPoint) -> Void

    var body: some View {
        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
            ForEach(Array(state.files.enumerated()), id: \.element.path) { index, file in
                let currentFile = state.vcs.file(for: file.path) ?? file
                Section {
                    if !state.isCollapsed(file.path) {
                        DiffBodyView(
                            isLoading: state.vcs.diffCache.isLoading(file.path),
                            error: state.vcs.diffCache.error(for: file.path),
                            diff: state.vcs.diffCache.diff(for: file.path),
                            filePath: file.path,
                            mode: state.mode,
                            onLoadFull: { state.refresh(forceFull: true) },
                            onViewMore: { state.vcs.expandDiffContext(filePath: file.path, direction: $0) },
                            onCommentRequest: onCommentRequest,
                            comments: state.comments(for: file.path),
                            suppressLeadingTopBorder: true
                        )
                    }
                } header: {
                    GithubDiffFileHeader(
                        isCollapsed: Binding(
                            get: { state.isCollapsed(file.path) },
                            set: { state.setCollapsed($0, filePath: file.path) }
                        ),
                        file: currentFile,
                        stats: state.vcs.displayedStats(for: currentFile),
                        suppressLeadingTopBorder: index == 0,
                        onStage: { state.vcs.stageFile(file.path) },
                        onUnstage: { state.vcs.unstageFile(file.path) },
                        onStash: { state.vcs.stashFile(file.path) },
                        onRevert: { state.vcs.discardFile(file.path) },
                        onComment: onCommentRequest,
                        comments: state.comments(for: file.path).filter { if case .file = $0.anchor { true } else { false } }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GithubDiffFileHeader: View {
    @Binding var isCollapsed: Bool
    let file: GitStatusFile
    let stats: VCSTabState.FileStats
    let suppressLeadingTopBorder: Bool
    let onStage: () -> Void
    let onUnstage: () -> Void
    let onStash: () -> Void
    let onRevert: () -> Void
    let onComment: (DiffCommentAnchor, CGPoint) -> Void
    let comments: [DiffComment]

    var body: some View {
        HStack(spacing: 8) {
            FileHeaderIconButton(
                symbol: isCollapsed ? "checkmark.square.fill" : "square",
                label: isCollapsed ? "Viewed - show diff" : "Mark viewed and collapse",
                selected: isCollapsed,
                action: { isCollapsed.toggle() }
            )

            FileDiffIcon()
                .stroke(KajiTheme.fgDim, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                .frame(width: 12, height: 12)
            Text(file.path)
                .kajiFont(size: 12, weight: .semibold)
                .foregroundStyle(KajiTheme.fg)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(file.paletteStatusText)
                .kajiFont(size: 10, weight: .semibold, design: .monospaced)
                .foregroundStyle(KajiTheme.fgMuted)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(KajiTheme.surface, in: Capsule())
            Spacer(minLength: 0)
            statsView
            commentButton
            actionButtons
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(KajiTheme.secondaryBackground)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(headerAccent)
                .frame(width: 3)
        }
        .overlay(alignment: .top) {
            if !suppressLeadingTopBorder {
                Rectangle().fill(KajiTheme.border).frame(height: 1)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(KajiTheme.border).frame(height: 1)
        }
    }

    private var headerAccent: Color {
        if file.xStatus == "?", file.yStatus == "?" {
            return KajiTheme.accent
        }
        if file.xStatus == "D" || file.yStatus == "D" {
            return KajiTheme.diffRemoveFg
        }
        if file.xStatus == "A" || file.yStatus == "A" || file.isStaged {
            return KajiTheme.diffAddFg
        }
        if file.isUnstaged {
            return KajiTheme.diffHunkFg
        }
        return KajiTheme.borderStrong
    }

    private var commentButton: some View {
        FileCommentAnchorButton(
            filePath: file.path,
            symbol: comments.isEmpty ? "text.bubble" : "text.bubble.fill",
            accessibilityLabel: comments.isEmpty ? "Comment on file" : "Edit file comment",
            tintColor: comments.isEmpty ? .secondaryLabelColor : .controlAccentColor,
            comments: comments,
            selected: !comments.isEmpty,
            action: { point in onComment(.file(path: file.path), point) }
        )
    }

    private var actionButtons: some View {
        HStack(spacing: 0) {
            if file.isStaged {
                FileHeaderIconButton(symbol: "minus", label: "Unstage", action: onUnstage)
            }
            if file.isUnstaged {
                FileHeaderIconButton(symbol: "plus", label: "Stage", action: onStage)
            }
            FileHeaderIconButton(symbol: "archivebox", label: "Stash file", action: onStash)
            FileHeaderIconButton(symbol: "arrow.uturn.backward", label: "Revert file", action: onRevert)
        }
    }

    private var statsView: some View {
        HStack(spacing: 8) {
            if stats.binary {
                Text("Binary")
                    .kajiFont(size: 10, weight: .medium)
                    .foregroundStyle(KajiTheme.fgDim)
            }
            if let additions = stats.additions, additions > 0 {
                Text("+\(additions)")
                    .kajiFont(size: 11, weight: .semibold, design: .monospaced)
                    .foregroundStyle(KajiTheme.diffAddFg)
            }
            if let deletions = stats.deletions, deletions > 0 {
                Text("-\(deletions)")
                    .kajiFont(size: 11, weight: .semibold, design: .monospaced)
                    .foregroundStyle(KajiTheme.diffRemoveFg)
            }
        }
    }
}

private struct FileHeaderIconButton: View {
    let symbol: String
    let label: String
    var selected = false
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        KajiIcon(systemName: symbol, size: 11)
            .foregroundStyle(selected || isHovering ? KajiTheme.fg : KajiTheme.fgMuted)
            .frame(width: 22, height: 22)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .onTapGesture(perform: action)
            .onHover { isHovering = $0 }
            .kajiPointer()
            .help(label)
    }

    private var backgroundColor: Color {
        if isHovering { return KajiTheme.surface }
        if selected { return KajiTheme.accent.opacity(0.14) }
        return .clear
    }
}

struct DiffCommentBubble: View {
    let comment: DiffComment

    var body: some View {
        HStack(spacing: 4) {
            KajiIcon(systemName: "text.bubble", size: 11)
                .foregroundStyle(KajiTheme.accent)
            Text(comment.text)
                .kajiFont(size: 10, weight: .medium)
                .foregroundStyle(KajiTheme.fg)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(KajiTheme.surface, in: Capsule())
        .overlay(Capsule().stroke(KajiTheme.border, lineWidth: 1))
    }
}
