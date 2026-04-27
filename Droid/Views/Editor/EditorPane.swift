import SwiftUI

struct EditorPane: View {
    @Bindable var state: EditorTabState
    let focused: Bool
    let onFocus: () -> Void
    @Environment(GhosttyService.self) private var ghostty
    @Environment(AppTypographySettings.self) private var typography

    var body: some View {
        VStack(spacing: 0) {
            EditorBreadcrumb(state: state)
            Rectangle().fill(DroidTheme.border).frame(height: 1)
            if state.awaitingLargeFileConfirmation {
                largeFileConfirmation
            } else if state.isLoading {
                loadingView
            } else if let error = state.errorMessage {
                errorView(error)
            } else {
                editorContentLayer
            }
        }
        .background(DroidTheme.bg)
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
    }

    private var editorContentLayer: some View {
        ZStack(alignment: .topTrailing) {
            editorMainContent

            if state.isIncrementalLoading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Loading full file...")
                        .droidFont(size: 11)
                        .foregroundStyle(DroidTheme.fgMuted)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(DroidTheme.bg.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(DroidTheme.border, lineWidth: 1)
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
                onFocus: onFocus
            )
        }
    }

    private var markdownPreviewContainer: some View {
        Group {
            if shouldDelayMarkdownPreview {
                markdownPreviewLoadingView
            } else {
                MarkdownWebView(
                    html: renderedMarkdownHTML,
                    content: renderedMarkdownContent,
                    filePath: state.filePath,
                    palette: markdownPalette,
                    syncScrollRequest: $state.markdownPreviewScrollRequest,
                    syncScrollRequestVersion: state.markdownPreviewScrollRequestVersion,
                    scrollSyncEnabled: usesMarkdownAnchorSync,
                    onScrollReport: { report in
                        state.markdownPreviewMaxScrollTop = report.maxScrollTop
                        state.markdownPreviewViewportHeight = report.clientHeight
                        let map = state.currentMarkdownSyncMap()
                        let output = state.markdownSyncCoordinator.previewDidScroll(scrollTop: report.scrollTop, map: map)
                        state.applyMarkdownSyncOutput(output)
                    },
                    onLayoutChanged: {
                        let map = state.currentMarkdownSyncMap()
                        let output = state.markdownSyncCoordinator.reissueAfterRelayout(map: map)
                        state.applyMarkdownSyncOutput(output)
                    },
                    onAnchorGeometryChanged: { geometries in
                        state.markdownPreviewGeometries = geometries
                    }
                )
            }
        }
        .background(DroidTheme.bg)
    }

    private var renderedMarkdownContent: String {
        _ = state.previewRefreshVersion
        return state.backingStore?.fullText() ?? ""
    }

    private var renderedMarkdownHTML: String {
        MarkdownRenderer.html(filePath: state.filePath, typography: typography)
    }

    private var markdownPalette: MarkdownRenderer.Palette {
        MarkdownRenderer.Palette(
            background: ghostty.backgroundColor,
            foreground: ghostty.foregroundColor,
            accent: ghostty.accentColor
        )
    }

    private var usesMarkdownAnchorSync: Bool {
        state.markdownViewMode == .split && state.markdownScrollSyncEnabled && !shouldDelayMarkdownPreview
    }

    private var shouldDelayMarkdownPreview: Bool {
        state.isMarkdownFile && state.isIncrementalLoading
    }

    private var markdownPreviewLoadingView: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Loading full markdown preview...")
                .droidFont(size: 12)
                .foregroundStyle(DroidTheme.fgMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DroidTheme.bg)
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
            DroidIcon(systemName: "exclamationmark.triangle", size: 28)
                .foregroundStyle(DroidTheme.fgMuted)
            Text("Large File")
                .droidFont(size: 14, weight: .semibold)
                .foregroundStyle(DroidTheme.fg)
            Text("This file is \(formattedLargeFileSize). Large files may slow down the editor.")
                .droidFont(size: 12)
                .foregroundStyle(DroidTheme.fgMuted)
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
                .droidFont(size: 12)
                .foregroundStyle(DroidTheme.diffRemoveFg)
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
                    DroidIcon(systemName: "arrow.up.and.down", size: 10)
                        .foregroundStyle(scrollSyncEnabled ? DroidTheme.accent : DroidTheme.fg)
                        .frame(width: 22, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(scrollSyncEnabled ? DroidTheme.surface : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(scrollSyncEnabled ? "Disable Scroll Sync" : "Enable Scroll Sync")
                .accessibilityLabel(scrollSyncEnabled ? "Disable Markdown Scroll Sync" : "Enable Markdown Scroll Sync")

                Rectangle()
                    .fill(DroidTheme.border)
                    .frame(width: 1, height: 14)
                    .padding(.horizontal, 2)
            }
            ForEach(EditorMarkdownViewMode.allCases, id: \.self) { candidate in
                Button {
                    mode = candidate
                } label: {
                    DroidIcon(systemName: candidate.symbol, size: 10)
                        .frame(width: 22, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(mode == candidate ? DroidTheme.surface : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(candidate.title)
                .accessibilityLabel("Markdown \(candidate.title) View")
            }
        }
        .padding(2)
        .background(DroidTheme.bg)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(DroidTheme.border, lineWidth: 1)
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
            DroidIcon(systemName: "doc.text", size: 10)
                .foregroundStyle(DroidTheme.fgDim)
            Text(relativePath)
                .droidFont(size: 11)
                .foregroundStyle(DroidTheme.fgMuted)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            if state.isModified {
                Circle()
                    .fill(DroidTheme.fg)
                    .frame(width: 6, height: 6)
            }
            if state.isReadOnly {
                Label {
                    Text("Read-only")
                } icon: {
                    DroidIcon(systemName: "lock.fill", size: 10)
                }
                .droidFont(size: 10, weight: .semibold)
                .foregroundStyle(DroidTheme.diffHunkFg)
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
                .droidFont(size: 10, design: .monospaced)
                .foregroundStyle(DroidTheme.fgDim)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(DroidTheme.bg)
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
