import SwiftUI

struct DiffViewerPane: View {
    @Bindable var state: DiffViewerTabState
    let focused: Bool
    let onFocus: () -> Void
    @State private var commentDraft: DiffCommentDraftRequest?

    var body: some View {
        VStack(spacing: 0) {
            DiffViewerBreadcrumb(state: state)
            Rectangle().fill(KajiTheme.border).frame(height: 1)
            ScrollView([.vertical]) {
                if state.showsAllChanges {
                    AllChangesDiffBody(state: state) { anchor, point in
                        commentDraft = DiffCommentDraftRequest(
                            anchor: anchor,
                            windowPoint: point,
                            initialText: state.comment(for: anchor)?.text ?? ""
                        )
                    }
                } else {
                    DiffBodyView(
                        isLoading: state.vcs.diffCache.isLoading(state.filePath),
                        error: state.vcs.diffCache.error(for: state.filePath),
                        diff: state.vcs.diffCache.diff(for: state.filePath),
                        filePath: state.filePath,
                        mode: state.mode,
                        onLoadFull: { state.refresh(forceFull: true) },
                        onViewMore: { state.vcs.expandDiffContext(filePath: state.filePath, direction: $0) },
                        onCommentRequest: { anchor, point in
                            commentDraft = DiffCommentDraftRequest(
                                anchor: anchor,
                                windowPoint: point,
                                initialText: state.comment(for: anchor)?.text ?? ""
                            )
                        },
                        comments: state.comments(for: state.filePath),
                        suppressLeadingTopBorder: true
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if state.showsAllChanges, !state.comments.isEmpty {
                DiffCommentPromptBar(state: state)
            }
        }
        .background(KajiTheme.bg)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { onFocus() })
        .overlay {
            DiffCommentWindowPopover(request: $commentDraft) { anchor, text in
                state.saveComment(anchor: anchor, text: text)
            }
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
        }
    }
}

private struct DiffCommentPromptBar: View {
    @Bindable var state: DiffViewerTabState
    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore
    @Environment(WorktreeStore.self) private var worktreeStore

    @State private var selectedSessionID: UUID?
    @State private var selectedProviderID = AskProvider.codex.rawValue

    private var project: Project? {
        projectStore.projects.first { $0.path == state.projectPath }
    }

    private var worktree: Worktree? {
        guard let project else { return nil }
        return worktreeStore.worktrees[project.id]?.first { $0.path == state.projectPath } ?? worktreeStore.primary(for: project.id)
    }

    private var sessions: [AskSessionOption] {
        guard let project, let worktree else { return [] }
        return AskSessionCatalog.sessions(
            projectID: project.id,
            worktreeID: worktree.id,
            worktrees: [worktree],
            appState: appState
        ).filter { $0.provider != .terminal }
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("\(state.comments.count) diff comment\(state.comments.count == 1 ? "" : "s")")
                .kajiFont(size: 11, weight: .semibold)
                .foregroundStyle(KajiTheme.fgMuted)

            Picker("Session", selection: $selectedSessionID) {
                Text("New session").tag(UUID?.none)
                ForEach(sessions) { session in
                    Text("\(session.providerTitle) - \(session.title)").tag(Optional(session.id))
                }
            }
            .labelsHidden()
            .frame(width: 220)

            if selectedSessionID == nil {
                Picker("Agent", selection: $selectedProviderID) {
                    ForEach(AskProvider.allCases.filter { $0 != .terminal }) { provider in
                        Text(provider.title).tag(provider.rawValue)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
            }

            Button("Send prompt") { sendPrompt() }
                .buttonStyle(.plain)
                .kajiFont(size: 11, weight: .semibold)
                .foregroundStyle(KajiTheme.accent)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(KajiTheme.secondaryBackground)
        .overlay(alignment: .top) { Rectangle().fill(KajiTheme.border).frame(height: 1) }
    }

    private func sendPrompt() {
        guard let project, let worktree else { return }
        let prompt = state.commentPrompt
        Task { @MainActor in
            if let selectedSessionID, let session = sessions.first(where: { $0.id == selectedSessionID }) {
                await AskCommandDispatcher.send(
                    AskDispatchRequest(
                        prompt: prompt,
                        project: project,
                        worktree: worktree,
                        provider: session.provider,
                        sessionMode: .existingSession,
                        session: session,
                        history: nil,
                        skill: nil
                    ),
                    appState: appState
                )
                return
            }
            let provider = AskProvider(agentID: selectedProviderID)
            await AskCommandDispatcher.send(
                AskDispatchRequest(
                    prompt: prompt,
                    project: project,
                    worktree: worktree,
                    provider: provider,
                    sessionMode: .newTerminal,
                    session: nil,
                    history: nil,
                    skill: nil
                ),
                appState: appState
            )
        }
    }
}

private struct DiffViewerBreadcrumb: View {
    @Bindable var state: DiffViewerTabState

    private var loadedDiff: DiffCache.LoadedDiff? {
        guard !state.showsAllChanges else { return nil }
        return state.vcs.diffCache.diff(for: state.filePath)
    }

    private var allChangesStats: (additions: Int, deletions: Int) {
        state.files.reduce(into: (additions: 0, deletions: 0)) { result, file in
            let stats = state.vcs.displayedStats(for: file)
            result.additions += stats.additions ?? 0
            result.deletions += stats.deletions ?? 0
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            FileDiffIcon()
                .stroke(KajiTheme.fgDim, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .frame(width: 11, height: 11)

            Text(state.showsAllChanges ? "All Changes" : state.filePath)
                .kajiFont(size: 11)
                .foregroundStyle(KajiTheme.fgMuted)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            if state.showsAllChanges {
                Text("\(state.files.count) files")
                    .kajiFont(size: 10, weight: .semibold)
                    .foregroundStyle(KajiTheme.fgMuted)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(KajiTheme.surface, in: Capsule())
            } else if state.isStaged {
                Text("Staged")
                    .kajiFont(size: 10, weight: .semibold)
                    .foregroundStyle(KajiTheme.fgMuted)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(KajiTheme.surface, in: Capsule())
            }

            if state.showsAllChanges {
                let stats = allChangesStats
                if stats.additions > 0 {
                    Text("+\(stats.additions)")
                        .kajiFont(size: 11, weight: .semibold, design: .monospaced)
                        .foregroundStyle(KajiTheme.diffAddFg)
                }
                if stats.deletions > 0 {
                    Text("-\(stats.deletions)")
                        .kajiFont(size: 11, weight: .semibold, design: .monospaced)
                        .foregroundStyle(KajiTheme.diffRemoveFg)
                }
            } else if let diff = loadedDiff {
                if diff.additions > 0 {
                    Text("+\(diff.additions)")
                        .kajiFont(size: 11, weight: .semibold, design: .monospaced)
                        .foregroundStyle(KajiTheme.diffAddFg)
                }
                if diff.deletions > 0 {
                    Text("-\(diff.deletions)")
                        .kajiFont(size: 11, weight: .semibold, design: .monospaced)
                        .foregroundStyle(KajiTheme.diffRemoveFg)
                }
            }

            Spacer()

            modeToggle

            IconButton(symbol: "arrow.clockwise", size: 11, accessibilityLabel: "Refresh Diff") {
                state.refresh(forceFull: false)
            }
            .help("Refresh")
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(KajiTheme.bg)
    }

    private var modeToggle: some View {
        HStack(spacing: 0) {
            modeButton(.split, symbol: "rectangle.split.2x1", tooltip: "Side by side")
            modeButton(.unified, symbol: "rectangle", tooltip: "Inline")
        }
        .background(KajiTheme.surface, in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(KajiTheme.border, lineWidth: 1))
    }

    private func modeButton(_ mode: VCSTabState.ViewMode, symbol: String, tooltip: String) -> some View {
        let selected = state.mode == mode
        return Button {
            state.mode = mode
        } label: {
            KajiIcon(systemName: symbol, size: 10)
                .foregroundStyle(selected ? KajiTheme.fg : KajiTheme.fgMuted)
                .frame(width: 22, height: 20)
                .background(selected ? KajiTheme.bg : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}
