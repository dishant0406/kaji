import SwiftUI

struct EditorPane: View {
    @Bindable var state: EditorTabState
    let focused: Bool
    let onFocus: () -> Void
    let project: Project?
    let worktree: Worktree?
    @Environment(GhosttyService.self) private var ghostty
    @Environment(AppTypographySettings.self) private var typography
    @State private var showsOutline = false

    var body: some View {
        VStack(spacing: 0) {
            EditorBreadcrumb(state: state)
            Rectangle().fill(KajiTheme.border).frame(height: 1)
            if state.awaitingLargeFileConfirmation {
                largeFileConfirmation
            } else if state.isLoading {
                loadingView
            } else if let error = state.errorMessage {
                errorView(error)
            } else {
                editorContentLayer
            }
            EditorStatusBar(state: state)
        }
        .background(KajiTheme.bg)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { onFocus() })
        .onReceive(NotificationCenter.default.publisher(for: .findInTerminal)) { _ in
            guard focused else { return }
            if state.isMarkdownFile, state.markdownViewMode == .preview {
                state.markdownViewMode = .code
            }
            if !state.currentSelection.isEmpty {
                state.searchNeedle = state.currentSelection
            }
            state.searchVisible = true
            state.searchFocusVersion += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .inlineEdit)) { _ in
            guard focused else { return }
            state.requestInlineEdit()
        }
        .overlay {
            if state.inlineEditVisible {
                InlineEditOverlay(state: state, project: project, worktree: worktree)
            }
        }
    }

    private var editorContentLayer: some View {
        ZStack(alignment: .topTrailing) {
            editorMainContent

            if state.isIncrementalLoading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Loading full file...")
                        .kajiFont(size: 11)
                        .foregroundStyle(KajiTheme.fgMuted)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(KajiTheme.bg.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(KajiTheme.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.top, 6)
                .padding(.trailing, state.searchVisible && showsCodeEditor ? 260 : 8)
            }

            if state.searchVisible, showsCodeEditor {
                EditorSearchBar(
                    state: state,
                    onNext: {
                        state.navigateSearch(.next)
                    },
                    onPrevious: {
                        state.navigateSearch(.previous)
                    },
                    onReplace: {
                        state.requestReplaceCurrent()
                    },
                    onReplaceAll: {
                        state.requestReplaceAll()
                    },
                    onClose: {
                        state.searchVisible = false
                        state.editorFocusVersion += 1
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var editorMainContent: some View {
        if state.isMarkdownFile {
            switch state.markdownViewMode {
            case .code:
                codeEditorContainer
            case .preview:
                markdownPreviewContainer
            case .split:
                HSplitView {
                    codeEditorContainer
                    markdownPreviewContainer
                }
            }
        } else {
            codeEditorContainer
        }
    }

    private var codeEditorContainer: some View {
        HStack(spacing: 0) {
            CodeEditorView(
                state: state,
                typography: typography,
                themeVersion: ghostty.configVersion,
                showsVerticalScroller: true,
                focused: focused,
                searchNeedle: state.searchNeedle,
                searchNavigationVersion: state.searchNavigationVersion,
                searchNavigationDirection: state.searchNavigationDirection,
                searchCaseSensitive: state.searchCaseSensitive,
                searchUseRegex: state.searchUseRegex,
                replaceText: state.replaceText,
                replaceVersion: state.replaceVersion,
                replaceAllVersion: state.replaceAllVersion,
                editorFocusVersion: state.editorFocusVersion,
                symbolNavigationVersion: state.symbolNavigationVersion,
                lineNavigationVersion: state.lineNavigationVersion,
                inlineEditRequestVersion: state.inlineEditRequestVersion,
                inlineEditApplyVersion: state.inlineEditApplyVersion,
                onFocus: onFocus
            )
            if showsOutline {
                EditorOutlinePanel(symbols: state.symbols()) { symbol in
                    state.navigate(to: symbol)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                showsOutline.toggle()
            } label: {
                KajiIcon(systemName: "list.bullet.rectangle", size: 12)
                    .foregroundStyle(showsOutline ? KajiTheme.accent : KajiTheme.fgMuted)
                    .frame(width: 26, height: 24)
                    .background(KajiTheme.bg.opacity(0.72), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            .padding(.trailing, showsOutline ? 248 : 8)
            .help("Toggle Outline")
        }
    }

    private var markdownPreviewContainer: some View {
        Group {
            if shouldDelayMarkdownPreview {
                markdownPreviewLoadingView
            } else {
                NativeMarkdownView(content: renderedMarkdownContent, filePath: state.filePath)
            }
        }
        .background(KajiTheme.bg)
    }

    private var renderedMarkdownContent: String {
        _ = state.previewRefreshVersion
        return state.backingStore?.fullText() ?? ""
    }

    private var shouldDelayMarkdownPreview: Bool {
        state.isMarkdownFile && state.isIncrementalLoading
    }

    private var markdownPreviewLoadingView: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Loading full markdown preview...")
                .kajiFont(size: 12)
                .foregroundStyle(KajiTheme.fgMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KajiTheme.bg)
    }

    private var showsCodeEditor: Bool {
        !state.isMarkdownFile || state.markdownViewMode != .preview
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView().controlSize(.small)
            Spacer()
        }
    }

    private var largeFileConfirmation: some View {
        VStack(spacing: 16) {
            Spacer()
            KajiIcon(systemName: "exclamationmark.triangle", size: 28)
                .foregroundStyle(KajiTheme.fgMuted)
            Text("Large File")
                .kajiFont(size: 14, weight: .semibold)
                .foregroundStyle(KajiTheme.fg)
            Text("This file is \(formattedLargeFileSize). Large files may slow down the editor.")
                .kajiFont(size: 12)
                .foregroundStyle(KajiTheme.fgMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            HStack(spacing: 8) {
                Button("Cancel") {
                    state.cancelLargeFileOpen()
                }
                .keyboardShortcut(.cancelAction)
                Button("Open Anyway") {
                    state.confirmLargeFileOpen()
                }
                .keyboardShortcut(.defaultAction)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var formattedLargeFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: state.largeFileSize)
    }

    private func errorView(_ error: String) -> some View {
        VStack {
            Spacer()
            Text(error)
                .kajiFont(size: 12)
                .foregroundStyle(KajiTheme.diffRemoveFg)
            Spacer()
        }
    }
}

private struct EditorMarkdownModePicker: View {
    @Binding var mode: EditorMarkdownViewMode
    @Binding var scrollSyncEnabled: Bool

    var body: some View {
        HStack(spacing: 2) {
            if mode == .split {
                Button {
                    scrollSyncEnabled.toggle()
                } label: {
                    KajiIcon(systemName: "arrow.up.and.down", size: 10)
                        .foregroundStyle(scrollSyncEnabled ? KajiTheme.accent : KajiTheme.fg)
                        .frame(width: 22, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(scrollSyncEnabled ? KajiTheme.surface : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(scrollSyncEnabled ? "Disable Scroll Sync" : "Enable Scroll Sync")
                .accessibilityLabel(scrollSyncEnabled ? "Disable Markdown Scroll Sync" : "Enable Markdown Scroll Sync")

                Rectangle()
                    .fill(KajiTheme.border)
                    .frame(width: 1, height: 14)
                    .padding(.horizontal, 2)
            }
            ForEach(EditorMarkdownViewMode.allCases, id: \.self) { candidate in
                Button {
                    mode = candidate
                } label: {
                    KajiIcon(systemName: candidate.symbol, size: 10)
                        .frame(width: 22, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(mode == candidate ? KajiTheme.surface : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(candidate.title)
                .accessibilityLabel("Markdown \(candidate.title) View")
            }
        }
        .padding(2)
        .background(KajiTheme.bg)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(KajiTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct EditorBreadcrumb: View {
    @Bindable var state: EditorTabState

    private var relativePath: String {
        let full = state.filePath
        let base = state.projectPath
        guard full.hasPrefix(base) else { return state.fileName }
        var rel = String(full.dropFirst(base.count))
        if rel.hasPrefix("/") { rel = String(rel.dropFirst()) }
        return rel
    }

    var body: some View {
        HStack(spacing: 4) {
            KajiIcon(systemName: "doc.text", size: 10)
                .foregroundStyle(KajiTheme.fgDim)
            Text(relativePath)
                .kajiFont(size: 11)
                .foregroundStyle(KajiTheme.fgMuted)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            if state.isModified {
                Circle()
                    .fill(KajiTheme.fg)
                    .frame(width: 6, height: 6)
            }
            if state.isReadOnly {
                Label {
                    Text("Read-only")
                } icon: {
                    KajiIcon(systemName: "lock.fill", size: 10)
                }
                .kajiFont(size: 10, weight: .semibold)
                .foregroundStyle(KajiTheme.diffHunkFg)
            }
            Spacer()
            if state.isMarkdownFile {
                EditorMarkdownModePicker(
                    mode: $state.markdownViewMode,
                    scrollSyncEnabled: $state.markdownScrollSyncEnabled
                )
                .padding(.trailing, 6)
            }
            Text("Ln \(state.cursorLine), Col \(state.cursorColumn)")
                .kajiFont(size: 10, design: .monospaced)
                .foregroundStyle(KajiTheme.fgDim)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(KajiTheme.bg)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(breadcrumbAccessibilityLabel)
    }

    private var breadcrumbAccessibilityLabel: String {
        var label = relativePath
        if state.isModified { label += ", modified" }
        if state.isReadOnly { label += ", read-only" }
        label += ", Line \(state.cursorLine), Column \(state.cursorColumn)"
        return label
    }
}
