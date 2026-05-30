import AppKit
import SwiftUI

struct VCSTabView: View {
    @Bindable var state: VCSTabState
    let focused: Bool
    let onFocus: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore
    @Environment(WorktreeStore.self) private var worktreeStore
    @State private var showDiscardAllConfirmation = false
    @State private var pendingDiscardPath: String?
    @State private var showCreateBranchModal = false
    @State private var showCreatePRModal = false
    @State private var showWorktreePopover = false
    @State private var pendingClosePR: GitRepositoryService.PRInfo?
    private var commitEnabled: Bool {
        state.hasStagedChanges && !state.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var owningProject: Project? {
        if let id = worktreeStore.projectID(forWorktreePath: state.projectPath) {
            return projectStore.projects.first { $0.id == id }
        }
        return projectStore.projects.first { $0.path == state.projectPath }
    }

    private var activeWorktreeForTab: Worktree? {
        guard let project = owningProject else { return nil }
        return worktreeStore.list(for: project.id).first { $0.path == state.projectPath }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(KajiTheme.border).frame(height: 1)
            content
        }
        .background(KajiTheme.bg)
        .contentShape(Rectangle())
        .onTapGesture(perform: onFocus)
        .overlay { branchModalOverlay }
        .overlay { prModalOverlay }
        .onAppear {
            if !state.hasCompletedInitialLoad, !state.isLoadingFiles {
                state.refresh()
            }
        }
        .onChange(of: state.projectPath) {
            if !state.hasCompletedInitialLoad, !state.isLoadingFiles {
                state.refresh()
            }
        }
        .onChange(of: state.showPushUpstreamConfirmation) { _, show in
            guard show else { return }
            state.showPushUpstreamConfirmation = false
            presentPushUpstreamConfirmation()
        }
        .onChange(of: showDiscardAllConfirmation) { _, show in
            guard show else { return }
            showDiscardAllConfirmation = false
            presentDiscardConfirmation(
                title: "Discard All Changes?",
                message: "This will discard all uncommitted changes. This cannot be undone.",
                buttonTitle: "Discard All"
            ) {
                state.discardAll()
            }
        }
        .onChange(of: pendingDiscardPath) { _, path in
            guard let path else { return }
            pendingDiscardPath = nil
            let fileName = (path as NSString).lastPathComponent
            presentDiscardConfirmation(
                title: "Discard Changes?",
                message: "Discard changes to \(fileName)?",
                buttonTitle: "Discard"
            ) {
                state.discardFile(path)
            }
        }
        .onChange(of: pendingClosePR?.number) { _, number in
            guard number != nil, let prInfo = pendingClosePR else { return }
            pendingClosePR = nil
            presentClosePRConfirmation(prInfo: prInfo)
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { state.statusIsError && state.statusMessage != nil },
                set: { if !$0 { state.statusMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { state.statusMessage = nil }
        } message: {
            if let message = state.statusMessage {
                Text(message)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            worktreeTrigger

            BranchPicker(
                currentBranch: state.branchName,
                branches: state.branches,
                isLoading: state.isLoadingBranches,
                onSelect: { state.switchBranch($0) },
                onRefresh: { state.loadBranches() },
                onCreateBranch: { showCreateBranchModal = true },
                onDeleteBranch: { branch in presentDeleteBranchConfirmation(branch) }
            )

            PRPill(
                state: state,
                onRequestCreate: { requestOpenPR() },
                onRequestMerge: { prInfo, method in performMerge(prInfo: prInfo, method: method) },
                onRequestClose: { prInfo in pendingClosePR = prInfo }
            )

            Spacer(minLength: 0)

            IconButton(symbol: "arrow.clockwise", accessibilityLabel: "Refresh") {
                state.refresh()
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(KajiTheme.secondaryBackground)
        .onChange(of: state.pullRequestInfo?.number) { _, number in
            guard number != nil, showCreatePRModal else { return }
            showCreatePRModal = false
        }
    }

    private func requestOpenPR() {
        state.openPullRequestError = nil
        state.loadRemoteBranches()
        showCreatePRModal = true
    }

    @ViewBuilder
    private var worktreeTrigger: some View {
        if let project = owningProject {
            Button {
                showWorktreePopover = true
            } label: {
                HStack(spacing: 4) {
                    KajiIcon(systemName: "square.stack.3d.up", size: 9)
                    Text(worktreeTriggerLabel)
                        .kajiFont(size: 11, weight: .medium)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 120, alignment: .leading)
                    KajiIcon(systemName: "chevron.down", size: 8)
                        .foregroundStyle(KajiTheme.fgDim)
                }
                .foregroundStyle(KajiTheme.fg)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(KajiTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
                .contentShape(RoundedRectangle(cornerRadius: KajiShape.tileRadius))
            }
            .buttonStyle(.plain)
            .help(worktreeTriggerLabel)
            .kajiPopover(isPresented: $showWorktreePopover, preferredEdge: .top) {
                WorktreePopover(
                    project: project,
                    isGitRepo: state.isGitRepo,
                    onDismiss: { showWorktreePopover = false },
                    onRequestCreate: {
                        showWorktreePopover = false
                        requestCreateWorktree()
                    }
                )
                .environment(appState)
                .environment(worktreeStore)
            }
        }
    }

    @ViewBuilder
    private var branchModalOverlay: some View {
        if showCreateBranchModal {
            KajiModalOverlay(onDismiss: { showCreateBranchModal = false }, content: {
                CreateBranchModal(
                    currentBranch: state.branchName,
                    onCreate: { name in
                        showCreateBranchModal = false
                        state.createAndSwitchBranch(name)
                    },
                    onCancel: { showCreateBranchModal = false }
                )
            })
        }
    }

    @ViewBuilder
    private var prModalOverlay: some View {
        if showCreatePRModal {
            KajiModalOverlay(onDismiss: dismissPRModal) {
                CreatePRModal(
                    context: .init(
                        currentBranch: state.branchName ?? "",
                        defaultBranch: state.defaultBranch,
                        availableBaseBranches: state.remoteBranches,
                        isLoadingBranches: state.isLoadingRemoteBranches,
                        hasStagedChanges: state.hasStagedChanges,
                        hasUnstagedChanges: !state.unstagedFiles.isEmpty
                    ),
                    inProgress: state.isOpeningPullRequest,
                    errorMessage: state.openPullRequestError,
                    onSubmit: { base, title, body, branchStrategy, includeMode, draft in
                        ToastState.shared.show("Creating pull request…")
                        state.openPullRequest(
                            VCSTabState.PRCreateRequest(
                                baseBranch: base,
                                title: title,
                                body: body,
                                branchStrategy: branchStrategy,
                                includeMode: includeMode,
                                draft: draft
                            )
                        )
                    },
                    onCancel: dismissPRModal
                )
            }
        }
    }

    private func dismissPRModal() {
        state.openPullRequestError = nil
        showCreatePRModal = false
    }

    private var worktreeTriggerLabel: String {
        guard let worktree = activeWorktreeForTab else { return "default" }
        if worktree.isPrimary {
            return worktree.name.isEmpty ? "default" : worktree.name
        }
        return worktree.name
    }

    private func requestCreateWorktree() {
        guard let projectID = owningProject?.id else { return }
        NotificationCenter.default.post(
            name: .requestCreateWorktreeModal,
            object: nil,
            userInfo: ["projectID": projectID]
        )
    }

    private func performMerge(prInfo: GitRepositoryService.PRInfo, method: GitRepositoryService.PRMergeMethod) {
        if prInfo.checks.status == .failure || prInfo.checks.status == .pending {
            presentChecksMergeConfirmation(prInfo: prInfo, method: method)
            return
        }
        continueMergeAfterChecks(prInfo: prInfo, method: method)
    }

    private func continueMergeAfterChecks(prInfo: GitRepositoryService.PRInfo, method: GitRepositoryService.PRMergeMethod) {
        if state.hasAnyChanges {
            presentDirtyMergeConfirmation(prInfo: prInfo, method: method)
            return
        }
        executeMerge(prInfo: prInfo, method: method)
    }

    private func presentChecksMergeConfirmation(prInfo: GitRepositoryService.PRInfo, method: GitRepositoryService.PRMergeMethod) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              window.attachedSheet == nil
        else { return }

        let isFailure = prInfo.checks.status == .failure
        let messageText = isFailure
            ? "Merge PR #\(prInfo.number) with failing checks?"
            : "Merge PR #\(prInfo.number) while checks are still running?"
        let informativeText = isFailure
            ? "\(prInfo.checks.failing) check(s) are failing. Merging now may introduce broken code into the base branch."
            : "\(prInfo.checks.pending) check(s) are still running. Merging now will bypass them."

        let alert = NSAlert()
        alert.messageText = messageText
        alert.informativeText = informativeText
        alert.alertStyle = .warning
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "Merge Anyway")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.keyEquivalent = ""
        alert.buttons.last?.keyEquivalent = "\u{1b}"

        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            continueMergeAfterChecks(prInfo: prInfo, method: method)
        }
    }

    private func executeMerge(prInfo: GitRepositoryService.PRInfo, method: GitRepositoryService.PRMergeMethod) {
        let project = owningProject
        let worktree = activeWorktreeForTab
        let defaultBranch = state.defaultBranch
        let isWorktreeMerge = worktree.map { !$0.isPrimary } ?? false
        state.mergePullRequest(method: method, deleteBranch: !isWorktreeMerge) { _, mergedBranch in
            ToastState.shared.show("Merged PR #\(prInfo.number)")
            Task { @MainActor in
                await cleanupAfterMerge(
                    mergedBranch: mergedBranch,
                    project: project,
                    worktree: worktree,
                    defaultBranch: defaultBranch
                )
            }
        }
    }

    private func presentDirtyMergeConfirmation(prInfo: GitRepositoryService.PRInfo, method: GitRepositoryService.PRMergeMethod) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              window.attachedSheet == nil
        else { return }

        let worktree = activeWorktreeForTab
        let willDiscard = worktree.map { !$0.isPrimary } ?? false

        let worktreeWarning = """
        You have uncommitted changes in this worktree. After the merge, the worktree will be \
        removed and those changes will be lost permanently.
        """
        let branchWarning = """
        You have uncommitted changes on this branch. After the merge, this branch will be \
        deleted on the remote and those changes will no longer belong to any branch.
        """

        let alert = NSAlert()
        alert.messageText = "Merge PR #\(prInfo.number) with uncommitted changes?"
        alert.informativeText = willDiscard ? worktreeWarning : branchWarning
        alert.alertStyle = .critical
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "Merge Anyway")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.keyEquivalent = ""
        alert.buttons.last?.keyEquivalent = "\u{1b}"

        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            executeMerge(prInfo: prInfo, method: method)
        }
    }

    private func cleanupAfterMerge(
        mergedBranch: String,
        project: Project?,
        worktree: Worktree?,
        defaultBranch: String?
    ) async {
        if let project, let worktree, worktree.canBeRemoved {
            removeWorktreeAfterMerge(project: project, worktree: worktree, mergedBranch: mergedBranch)
            return
        }

        if let defaultBranch, defaultBranch != mergedBranch {
            await state.switchBranchAndRefresh(defaultBranch)
        }
    }

    private func removeWorktreeAfterMerge(project: Project, worktree: Worktree, mergedBranch: String) {
        let repoPath = project.path
        let remaining = worktreeStore.list(for: project.id).filter { $0.id != worktree.id }
        let replacement = remaining.first(where: { $0.isPrimary }) ?? remaining.first
        appState.removeWorktree(
            projectID: project.id,
            worktree: worktree,
            replacement: replacement
        )
        worktreeStore.remove(worktreeID: worktree.id, from: project.id)
        Task.detached {
            await WorktreeStore.cleanupOnDisk(
                worktree: worktree,
                repoPath: repoPath
            )
            try? await GitRepositoryService().deleteRemoteBranch(
                repoPath: repoPath,
                branch: mergedBranch
            )
        }
    }

    private func presentClosePRConfirmation(prInfo: GitRepositoryService.PRInfo) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              window.attachedSheet == nil
        else { return }

        let alert = NSAlert()
        alert.messageText = "Close PR #\(prInfo.number)?"
        alert.informativeText = "This will close the pull request on GitHub without merging. You can reopen it later."
        alert.alertStyle = .warning
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "Close PR")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.keyEquivalent = "\r"
        alert.buttons.last?.keyEquivalent = "\u{1b}"

        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            state.closePullRequest {}
        }
    }

    @ViewBuilder
    private var content: some View {
        if state.isLoadingFiles {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if state.files.isEmpty, state.errorMessage != nil {
            Text(state.errorMessage ?? "")
                .kajiFont(size: 12)
                .foregroundStyle(KajiTheme.fgMuted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                commitArea
                SectionSplitLayout(
                    state: state,
                    onFocus: onFocus,
                    showDiscardAllConfirmation: $showDiscardAllConfirmation,
                    pendingDiscardPath: $pendingDiscardPath,
                    onOpenInEditor: openFileInEditor,
                    onOpenDiff: openDiffInTab
                )
            }
        }
    }

    private var commitArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Commit")
                .kajiFont(size: 11, weight: .semibold)
                .foregroundStyle(KajiTheme.fgDim)
            KajiTextArea(
                placeholder: "Commit message. Use ⌘↵ to commit on \(state.branchName ?? "branch").",
                text: $state.commitMessage,
                minHeight: 64,
                maxHeight: 104,
                onCommandEnter: { state.commit() }
            )
            HStack(spacing: 8) {
                commitButton
                pullButton
                pushButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(KajiTheme.secondaryBackground)
    }

    private var commitButton: some View {
        Button {
            state.commit()
        } label: {
            HStack(spacing: 6) {
                if state.isCommitting {
                    KajiSpinner(size: 11, lineWidth: 1.4, color: KajiTheme.bg)
                } else {
                    KajiIcon(systemName: "checkmark", size: 11)
                }
                Text("Commit")
                if state.hasStagedChanges {
                    Text("\(state.stagedFiles.count)")
                        .kajiFont(size: 11, weight: .semibold, design: .monospaced)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(KajiButtonStyle(commitEnabled ? .primary : .secondary, size: .small))
        .opacity(commitEnabled || state.isCommitting ? 1 : 0.46)
        .disabled(!commitEnabled || state.isCommitting)
        .kajiChangeFeedback(KajiMotion.successFeedback, value: state.stagedFiles.count, isEnabled: !state.isCommitting)
        .kajiChangeFeedback(KajiMotion.invalidFeedback, value: commitEnabled, isEnabled: !commitEnabled && state.hasStagedChanges)
        .help("Commit staged changes")
    }

    private var pullButton: some View {
        Button {
            state.pull()
        } label: {
            HStack(spacing: 6) {
                if state.isPulling {
                    KajiSpinner(size: 11, lineWidth: 1.4, color: KajiTheme.fg)
                } else {
                    KajiIcon(systemName: "arrow.down", size: 11)
                }
                Text("Pull")
                if state.aheadBehind.behind > 0 {
                    Text("\(state.aheadBehind.behind)")
                        .kajiFont(size: 11, weight: .semibold, design: .monospaced)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(KajiButtonStyle(.secondary, size: .small))
        .disabled(state.isPulling)
        .kajiChangeFeedback(KajiMotion.successFeedback, value: state.aheadBehind.behind, isEnabled: !state.isPulling)
        .help(state.aheadBehind.behind > 0
            ? "Pull \(state.aheadBehind.behind) commit\(state.aheadBehind.behind == 1 ? "" : "s") from origin"
            : "Pull from origin")
    }

    private var pushButton: some View {
        Button {
            state.push()
        } label: {
            HStack(spacing: 6) {
                if state.isPushing {
                    KajiSpinner(size: 11, lineWidth: 1.4, color: KajiTheme.fg)
                } else {
                    KajiIcon(systemName: "arrow.up", size: 11)
                }
                Text("Push")
                if state.aheadBehind.ahead > 0 {
                    Text("\(state.aheadBehind.ahead)")
                        .kajiFont(size: 11, weight: .semibold, design: .monospaced)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(KajiButtonStyle(.secondary, size: .small))
        .disabled(state.isPushing)
        .kajiChangeFeedback(KajiMotion.successFeedback, value: state.aheadBehind.ahead, isEnabled: !state.isPushing)
        .help(state.aheadBehind.ahead > 0
            ? "Push \(state.aheadBehind.ahead) commit\(state.aheadBehind.ahead == 1 ? "" : "s") to origin"
            : "Push to origin")
    }

    private static let actionButtonHeight: CGFloat = 28

    private func presentDiscardConfirmation(
        title: String,
        message: String,
        buttonTitle: String,
        onConfirm: @escaping () -> Void
    ) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              window.attachedSheet == nil
        else { return }

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: buttonTitle)
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.keyEquivalent = "\r"
        alert.buttons.last?.keyEquivalent = "\u{1b}"

        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn {
                onConfirm()
            }
        }
    }

    private func presentDeleteBranchConfirmation(_ branch: String) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              window.attachedSheet == nil
        else { return }

        let alert = NSAlert()
        alert.messageText = "Delete Branch?"
        alert.informativeText = "This will permanently delete the local branch \"\(branch)\". Unmerged commits on this branch will be lost."
        alert.alertStyle = .warning
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.keyEquivalent = "\r"
        alert.buttons.last?.keyEquivalent = "\u{1b}"

        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            Task { await state.deleteLocalBranch(branch) }
        }
    }

    private func presentPushUpstreamConfirmation() {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              window.attachedSheet == nil
        else { return }

        let branch = state.branchName ?? "current branch"
        let alert = NSAlert()
        alert.messageText = "Push to Remote?"
        alert.informativeText = "The branch \"\(branch)\" has no upstream on the remote. Push and set upstream to origin/\(branch)?"
        alert.alertStyle = .informational
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "Push")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.keyEquivalent = "\r"
        alert.buttons.last?.keyEquivalent = "\u{1b}"

        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn {
                state.pushSetUpstream()
            }
        }
    }

    private func openFileInEditor(_ relativePath: String) {
        guard let projectID = appState.activeProjectID else { return }
        let fullPath = state.projectPath.hasSuffix("/")
            ? state.projectPath + relativePath
            : state.projectPath + "/" + relativePath
        appState.openFile(fullPath, projectID: projectID)
    }

    private func openDiffInTab(_ relativePath: String, isStaged: Bool) {
        guard let projectID = appState.activeProjectID else { return }
        appState.openDiffViewer(vcs: state, filePath: relativePath, isStaged: isStaged, projectID: projectID)
    }
}

struct PRPill: View {
    @Bindable var state: VCSTabState
    let onRequestCreate: () -> Void
    let onRequestMerge: (GitRepositoryService.PRInfo, GitRepositoryService.PRMergeMethod) -> Void
    let onRequestClose: (GitRepositoryService.PRInfo) -> Void

    @State private var showPRPopover = false

    var body: some View {
        switch state.prLaunchState {
        case .hidden:
            EmptyView()
        case .ghMissing:
            ghMissingPill
        case .canCreate:
            createPRPill
        case let .hasPR(info):
            hasPRPill(info: info)
        }
    }

    private var ghMissingPill: some View {
        pillContainer(
            icon: "exclamationmark.triangle",
            text: "Install gh",
            tint: KajiTheme.fgMuted,
            disabled: true
        ) {}
            .help("Install GitHub CLI to create pull requests: brew install gh")
    }

    private var createPRPill: some View {
        pillContainer(
            icon: "arrow.triangle.pull",
            text: "Create PR",
            tint: KajiTheme.accent,
            disabled: state.isOpeningPullRequest,
            action: onRequestCreate
        )
        .help("Create a pull request")
    }

    private func hasPRPill(info: GitRepositoryService.PRInfo) -> some View {
        Button {
            showPRPopover = true
        } label: {
            HStack(spacing: 6) {
                KajiIcon(systemName: prStateIcon(info), size: 10)
                    .foregroundStyle(prStateColor(info))
                Text("PR #\(info.number)")
                    .kajiFont(size: 11, weight: .semibold)
                    .foregroundStyle(KajiTheme.fg)
                KajiIcon(systemName: "chevron.down", size: 8)
                    .foregroundStyle(KajiTheme.fgDim)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(KajiTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
            .overlay(RoundedRectangle(cornerRadius: KajiShape.tileRadius).stroke(prStateColor(info).opacity(0.24), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        }
        .buttonStyle(.plain)
        .help("Pull request #\(info.number)")
        .kajiPopover(isPresented: $showPRPopover, preferredEdge: .top) {
            PRPopover(
                state: state,
                info: info,
                onMerge: { method in
                    let needsConfirmation = state.hasAnyChanges
                        || info.checks.status == .failure
                        || info.checks.status == .pending
                    if needsConfirmation {
                        showPRPopover = false
                    }
                    onRequestMerge(info, method)
                },
                onClose: {
                    showPRPopover = false
                    onRequestClose(info)
                },
                onOpenInBrowser: {
                    showPRPopover = false
                    if let url = URL(string: info.url) {
                        NSWorkspace.shared.open(url)
                    }
                },
                onRefresh: {
                    state.refreshPullRequest()
                }
            )
        }
        .onChange(of: state.pullRequestInfo?.number) { _, number in
            if number == nil, showPRPopover {
                showPRPopover = false
            }
        }
    }

    private func prStateIcon(_ info: GitRepositoryService.PRInfo) -> String {
        if info.state == .open {
            switch info.checks.status {
            case .failure: return "xmark.octagon.fill"
            case .pending: return "clock"
            default: break
            }
        }
        switch info.state {
        case .open: return info.isDraft ? "pencil.circle" : "arrow.triangle.pull"
        case .merged: return "checkmark.circle.fill"
        case .closed: return "xmark.circle"
        }
    }

    private func prStateColor(_ info: GitRepositoryService.PRInfo) -> Color {
        if info.state == .open {
            switch info.checks.status {
            case .failure: return KajiTheme.diffRemoveFg
            case .pending: return KajiTheme.fgMuted
            default: break
            }
        }
        switch info.state {
        case .open: return info.isDraft ? KajiTheme.fgMuted : KajiTheme.diffAddFg
        case .merged: return KajiTheme.accent
        case .closed: return KajiTheme.diffRemoveFg
        }
    }

    private func pillContainer(
        icon: String,
        text: String,
        tint: Color,
        disabled: Bool,
        action: @escaping () -> Void = {}
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                KajiIcon(systemName: icon, size: 10)
                Text(text)
                    .kajiFont(size: 11, weight: .semibold)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(KajiTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
            .overlay(RoundedRectangle(cornerRadius: KajiShape.tileRadius).stroke(tint.opacity(0.24), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

struct PRPopover: View {
    @Bindable var state: VCSTabState
    let info: GitRepositoryService.PRInfo
    let onMerge: (GitRepositoryService.PRMergeMethod) -> Void
    let onClose: () -> Void
    let onOpenInBrowser: () -> Void
    let onRefresh: () -> Void

    @State private var mergeMethod: GitRepositoryService.PRMergeMethod = .squash

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                KajiIcon(systemName: stateIcon, size: 14)
                    .foregroundStyle(stateColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Pull Request #\(info.number)")
                        .kajiFont(size: 12, weight: .semibold)
                    Text(stateLabel)
                        .kajiFont(size: 10)
                        .foregroundStyle(KajiTheme.fgMuted)
                }
                Spacer(minLength: 0)
                Button {
                    onRefresh()
                } label: {
                    Group {
                        if state.isRefreshingPullRequest {
                            ProgressView().controlSize(.mini)
                        } else {
                            KajiIcon(systemName: "arrow.clockwise", size: 11)
                                .foregroundStyle(KajiTheme.fgMuted)
                        }
                    }
                    .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .disabled(state.isRefreshingPullRequest)
                .help("Refresh")
            }

            VStack(alignment: .leading, spacing: 4) {
                infoRow(label: "Base", value: info.baseBranch)
                if let label = mergeableLabel {
                    infoRow(
                        label: "Mergeable",
                        value: label.text,
                        valueColor: label.color
                    )
                }
                checksRow
            }

            Divider()

            Button(action: onOpenInBrowser) {
                HStack(spacing: 6) {
                    KajiIcon(systemName: "arrow.up.right.square", size: 11)
                    Text("Open on GitHub")
                        .kajiFont(size: 11, weight: .medium)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(KajiTheme.fg)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(KajiTheme.surface, in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)

            if info.state == .open {
                SegmentedPicker(
                    selection: $mergeMethod,
                    options: GitRepositoryService.PRMergeMethod.allCases.map { ($0, $0.shortLabel) }
                )

                Button { onMerge(mergeMethod) } label: {
                    HStack(spacing: 6) {
                        if state.isMergingPullRequest {
                            ProgressView().controlSize(.mini)
                        } else {
                            KajiIcon(systemName: "arrow.triangle.merge", size: 11)
                        }
                        Text(state.isMergingPullRequest ? "Merging…" : mergeMethod.label)
                            .kajiFont(size: 11, weight: .medium)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(mergeDisabled ? KajiTheme.fgDim : KajiTheme.bg)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(
                        mergeDisabled ? KajiTheme.surface : KajiTheme.accent,
                        in: RoundedRectangle(cornerRadius: 5)
                    )
                }
                .buttonStyle(.plain)
                .disabled(mergeDisabled)
                .help(mergeHelp)

                Button(action: onClose) {
                    HStack(spacing: 6) {
                        if state.isClosingPullRequest {
                            ProgressView().controlSize(.mini)
                        } else {
                            KajiIcon(systemName: "xmark.circle", size: 11)
                        }
                        Text("Close PR")
                            .kajiFont(size: 11, weight: .medium)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(KajiTheme.diffRemoveFg)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(KajiTheme.surface, in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .disabled(state.isClosingPullRequest)
            }
        }
        .padding(12)
        .frame(width: 260)
        .task(id: info.number) {
            onRefresh()
        }
    }

    private var mergeDisabled: Bool {
        if state.isMergingPullRequest { return true }
        if info.mergeable == false { return true }
        switch info.mergeStateStatus {
        case .dirty,
             .blocked,
             .behind,
             .draft: return true
        case .clean,
             .hasHooks,
             .unstable,
             .unknown: return false
        }
    }

    private var mergeHelp: String {
        if info.mergeable == false { return "This PR has conflicts and cannot be merged." }
        switch info.mergeStateStatus {
        case .dirty: return "This PR has conflicts and cannot be merged."
        case .behind: return "This branch is out of date with the base branch. Update it before merging."
        case .blocked: return "Merging is blocked by branch protection (required reviews or checks)."
        case .draft: return "This PR is a draft. Mark it ready for review before merging."
        case .unstable:
            return "Checks are failing or pending. You will be asked to confirm before merging."
        case .clean,
             .hasHooks,
             .unknown:
            if info.checks.status == .failure {
                return "Checks are failing. You will be asked to confirm before merging."
            }
            if info.checks.status == .pending {
                return "Checks are still running. You will be asked to confirm before merging."
            }
            return "Merge PR #\(info.number)"
        }
    }

    private var mergeableLabel: (text: String, color: Color)? {
        switch info.mergeStateStatus {
        case .dirty:
            return ("Conflicts", KajiTheme.diffRemoveFg)
        case .behind:
            return ("Behind base", KajiTheme.diffRemoveFg)
        case .blocked:
            return ("Blocked", KajiTheme.diffRemoveFg)
        case .draft:
            return ("Draft", KajiTheme.fgMuted)
        case .clean,
             .hasHooks:
            return ("Yes", KajiTheme.diffAddFg)
        case .unstable:
            return ("Yes (checks failing)", KajiTheme.diffAddFg)
        case .unknown:
            if info.mergeable == true { return ("Yes", KajiTheme.diffAddFg) }
            if info.mergeable == false { return ("Conflicts", KajiTheme.diffRemoveFg) }
            return nil
        }
    }

    @ViewBuilder
    private var checksRow: some View {
        switch info.checks.status {
        case .none:
            EmptyView()
        case .success:
            infoRow(
                label: "Checks",
                value: "\(info.checks.passing)/\(info.checks.total) passing",
                valueColor: KajiTheme.diffAddFg
            )
        case .pending:
            infoRow(
                label: "Checks",
                value: "\(info.checks.pending) running",
                valueColor: KajiTheme.fgMuted
            )
        case .failure:
            infoRow(
                label: "Checks",
                value: "\(info.checks.failing) failing",
                valueColor: KajiTheme.diffRemoveFg
            )
        }
    }

    private var stateIcon: String {
        if info.state == .open {
            switch info.checks.status {
            case .failure: return "xmark.octagon.fill"
            case .pending: return "clock"
            default: break
            }
        }
        switch info.state {
        case .open: return info.isDraft ? "pencil.circle" : "arrow.triangle.pull"
        case .merged: return "checkmark.circle.fill"
        case .closed: return "xmark.circle"
        }
    }

    private var stateColor: Color {
        if info.state == .open {
            switch info.checks.status {
            case .failure: return KajiTheme.diffRemoveFg
            case .pending: return KajiTheme.fgMuted
            default: break
            }
        }
        switch info.state {
        case .open: return info.isDraft ? KajiTheme.fgMuted : KajiTheme.diffAddFg
        case .merged: return KajiTheme.accent
        case .closed: return KajiTheme.diffRemoveFg
        }
    }

    private var stateLabel: String {
        switch info.state {
        case .open: info.isDraft ? "Draft · Open" : "Open"
        case .merged: "Merged"
        case .closed: "Closed"
        }
    }

    private func infoRow(label: String, value: String, valueColor: Color = KajiTheme.fg) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .kajiFont(size: 11)
                .foregroundStyle(KajiTheme.fgMuted)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .kajiFont(size: 11, weight: .medium, design: .monospaced)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }
}

private struct SectionSplitLayout: View {
    @Bindable var state: VCSTabState
    let onFocus: () -> Void
    @Binding var showDiscardAllConfirmation: Bool
    @Binding var pendingDiscardPath: String?
    let onOpenInEditor: (String) -> Void
    let onOpenDiff: (String, Bool) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let sectionHeaderHeight: CGFloat = 30

    private var hasStaged: Bool { !state.stagedFiles.isEmpty }

    private var sections: [SectionKind] {
        var result: [SectionKind] = []
        if hasStaged { result.append(.staged) }
        result.append(.changes)
        result.append(.history)
        return result
    }

    private func isCollapsed(_ kind: SectionKind) -> Bool {
        switch kind {
        case .staged: state.stagedCollapsed
        case .changes: state.changesCollapsed
        case .history: state.historyCollapsed
        }
    }

    private func toggleCollapsed(_ kind: SectionKind) {
        switch kind {
        case .staged: state.stagedCollapsed.toggle()
        case .changes: state.changesCollapsed.toggle()
        case .history:
            state.historyCollapsed.toggle()
            if !state.historyCollapsed, state.commits.isEmpty {
                state.loadCommits()
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            let allSections = sections
            let expandedSections = allSections.filter { !isCollapsed($0) }
            let collapsedSections = allSections.filter { isCollapsed($0) }
            let collapsedHeight = CGFloat(collapsedSections.count) * Self.sectionHeaderHeight
            let borderCount = CGFloat(allSections.count + 1)
            let availableForExpanded = max(0, geo.size.height - collapsedHeight - borderCount)
            let ratios = distributedRatios(allSections: allSections, expandedSections: expandedSections)

            VStack(spacing: 0) {
                ForEach(Array(allSections.enumerated()), id: \.element) { index, section in
                    let collapsed = isCollapsed(section)
                    let prevExpanded = previousExpandedSection(before: index, in: allSections)
                    let needsDraggableDivider = !collapsed && prevExpanded != nil

                    if needsDraggableDivider, let prev = prevExpanded {
                        sectionDivider(
                            above: prev,
                            below: section,
                            totalHeight: availableForExpanded,
                            allSections: allSections
                        )
                    } else {
                        Rectangle().fill(KajiTheme.border).frame(height: 1)
                    }

                    if collapsed {
                        sectionHeader(for: section, collapsed: true)
                            .frame(height: Self.sectionHeaderHeight)
                    } else {
                        let ratio = ratios[section] ?? 0
                        let sectionHeight = max(Self.sectionHeaderHeight, availableForExpanded * ratio)
                        sectionView(for: section, height: sectionHeight)
                    }
                }
                Rectangle().fill(KajiTheme.border).frame(height: 1)
            }
        }
    }

    private func distributedRatios(
        allSections: [SectionKind],
        expandedSections: [SectionKind]
    ) -> [SectionKind: CGFloat] {
        guard !expandedSections.isEmpty else { return [:] }

        let rawRatios: [CGFloat] = allSections.enumerated().compactMap { idx, section in
            guard !isCollapsed(section) else { return nil }
            return state.sectionRatios[safe: idx] ?? (1.0 / CGFloat(expandedSections.count))
        }

        let sum = rawRatios.reduce(0, +)
        guard sum > 0 else { return [:] }

        var result: [SectionKind: CGFloat] = [:]
        var rawIdx = 0
        for section in expandedSections {
            result[section] = rawRatios[rawIdx] / sum
            rawIdx += 1
        }
        return result
    }

    private func previousExpandedSection(before index: Int, in allSections: [SectionKind]) -> SectionKind? {
        for i in stride(from: index - 1, through: 0, by: -1) where !isCollapsed(allSections[i]) {
            return allSections[i]
        }
        return nil
    }

    private func sectionDivider(
        above: SectionKind,
        below: SectionKind,
        totalHeight: CGFloat,
        allSections: [SectionKind]
    ) -> some View {
        Rectangle().fill(KajiTheme.border).frame(height: 1)
            .overlay {
                Color.clear
                    .frame(height: 5)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { v in
                                guard totalHeight > 0 else { return }
                                let delta = v.translation.height / totalHeight

                                guard let aboveIdx = allSections.firstIndex(of: above),
                                      let belowIdx = allSections.firstIndex(of: below)
                                else { return }

                                var ratios = state.sectionRatios
                                let minRatio: CGFloat = 0.08

                                ratios[aboveIdx] += delta
                                ratios[belowIdx] -= delta

                                ratios[aboveIdx] = max(minRatio, ratios[aboveIdx])
                                ratios[belowIdx] = max(minRatio, ratios[belowIdx])

                                let sum = ratios.reduce(0, +)
                                if sum > 0 {
                                    ratios = ratios.map { $0 / sum }
                                }

                                state.sectionRatios = ratios
                            }
                    )
                    .onHover { on in
                        if on { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                    }
            }
    }

    @ViewBuilder
    private func sectionView(for section: SectionKind, height: CGFloat) -> some View {
        switch section {
        case .staged:
            VStack(spacing: 0) {
                sectionHeader(for: .staged, collapsed: false)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(state.stagedFiles) { file in
                            fileSection(file, isStaged: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(height: height)

        case .changes:
            VStack(spacing: 0) {
                sectionHeader(for: .changes, collapsed: false)
                if state.files.isEmpty {
                    Text("No changes")
                        .kajiFont(size: 12)
                        .foregroundStyle(KajiTheme.fgMuted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(state.unstagedFiles) { file in
                                fileSection(file, isStaged: false)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(height: height)

        case .history:
            VStack(spacing: 0) {
                sectionHeader(for: .history, collapsed: false)
                CommitHistoryView(state: state)
            }
            .frame(height: height)
        }
    }

    private func sectionHeader(for section: SectionKind, collapsed: Bool) -> some View {
        let isCollapsedState = collapsed

        return HStack(spacing: 6) {
            Button {
                withAnimation(KajiMotion.panel) { toggleCollapsed(section) }
            } label: {
                HStack(spacing: 6) {
                    KajiIcon(systemName: isCollapsedState ? "chevron.right" : "chevron.down", size: 9)
                        .foregroundStyle(KajiTheme.fgDim)
                        .frame(width: 10)

                    Text(section.title)
                        .kajiFont(size: 11, weight: .semibold)
                        .foregroundStyle(KajiTheme.fgMuted)
                }
            }
            .buttonStyle(.plain)

            Text("\(sectionCount(for: section))")
                .kajiFont(size: 11, weight: .semibold, design: .monospaced)
                .foregroundStyle(KajiTheme.fgDim)

            Spacer(minLength: 0)

            sectionActions(for: section)
        }
        .padding(.horizontal, 10)
        .frame(height: Self.sectionHeaderHeight)
        .background(KajiTheme.secondaryBackground)
        .animation(KajiMotion.fast, value: collapsed)
        .kajiChangeFeedback(KajiMotion.selectionFeedback, value: collapsed)
    }

    private func sectionCount(for section: SectionKind) -> Int {
        switch section {
        case .staged: state.stagedFiles.count
        case .changes: state.unstagedFiles.count
        case .history: state.commits.count
        }
    }

    @ViewBuilder
    private func sectionActions(for section: SectionKind) -> some View {
        switch section {
        case .staged:
            diffModeToggle
            expandCollapseButton(for: state.stagedFiles)
            IconButton(symbol: "minus", size: 11, accessibilityLabel: "Unstage All") {
                state.unstageAll()
            }
            .help("Unstage all")

        case .changes:
            diffModeToggle
            expandCollapseButton(for: state.unstagedFiles)
            IconButton(symbol: "plus", size: 11, accessibilityLabel: "Stage All") {
                state.stageAll()
            }
            .help("Stage all")

            IconButton(symbol: "arrow.uturn.backward", size: 11, accessibilityLabel: "Discard All Changes") {
                showDiscardAllConfirmation = true
            }
            .help("Discard all changes")

        case .history:
            IconButton(symbol: "arrow.clockwise", size: 11, accessibilityLabel: "Refresh History") {
                state.loadCommits()
            }
            .help("Refresh history")
        }
    }

    private var diffModeToggle: some View {
        Button {
            state.mode = state.mode == .unified ? .split : .unified
        } label: {
            KajiIcon(systemName: state.mode == .unified ? "rectangle.split.2x1" : "rectangle", size: 10)
                .foregroundStyle(KajiTheme.fgMuted)
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(state.mode == .unified ? "Switch to Split View" : "Switch to Unified View")
    }

    @ViewBuilder
    private func expandCollapseButton(for files: [GitStatusFile]) -> some View {
        let anyExpanded = files.contains { state.expandedFilePaths.contains($0.path) }
        Button {
            withAnimation(KajiMotion.panel) { state.setExpanded(files: files, expanded: !anyExpanded) }
        } label: {
            KajiIcon(
                systemName: anyExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                size: 10
            )
            .foregroundStyle(KajiTheme.fgMuted)
            .frame(width: 22, height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(anyExpanded ? "Collapse all" : "Expand all")
    }

    private func fileSection(_ file: GitStatusFile, isStaged: Bool) -> some View {
        let expanded = state.expandedFilePaths.contains(file.path)
        let stats = state.displayedStats(for: file)
        let statusText = isStaged ? file.stagedStatusText : file.unstagedStatusText

        return VStack(spacing: 0) {
            FileRow(
                file: file,
                statusText: statusText,
                expanded: expanded,
                stats: stats,
                isStaged: isStaged,
                onToggle: {
                    onFocus()
                    withAnimation(KajiMotion.panel) { state.toggleExpanded(filePath: file.path) }
                },
                onStage: { state.stageFile(file.path) },
                onUnstage: { state.unstageFile(file.path) },
                onDiscard: { pendingDiscardPath = file.path },
                onOpenInEditor: { onOpenInEditor(file.path) },
                onOpenDiff: { onOpenDiff(file.path, isStaged) }
            )

            if expanded {
                expandedDiff(for: file)
                    .transition(KajiMotion.disclosureTransition(reduceMotion: reduceMotion))
            }

            Rectangle().fill(KajiTheme.border).frame(height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(KajiMotion.panel, value: expanded)
    }

    private func expandedDiff(for file: GitStatusFile) -> some View {
        DiffBodyView(
            isLoading: state.diffCache.isLoading(file.path),
            error: state.diffCache.error(for: file.path),
            diff: state.diffCache.diff(for: file.path),
            filePath: file.path,
            mode: state.mode,
            onLoadFull: { state.loadFullDiff(filePath: file.path) },
            onViewMore: { hunkIndex, direction in
                state.expandDiffContext(filePath: file.path, hunkIndex: hunkIndex, direction: direction)
            },
            contextExpansion: { state.contextExpansion(filePath: file.path, hunkIndex: $0) }
        )
    }
}

private enum SectionKind: Hashable {
    case staged
    case changes
    case history

    var title: String {
        switch self {
        case .staged: "Staged Changes"
        case .changes: "Changes"
        case .history: "History"
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private struct FileRow: View {
    let file: GitStatusFile
    let statusText: String
    let expanded: Bool
    let stats: VCSTabState.FileStats
    let isStaged: Bool
    let onToggle: () -> Void
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
        case "M":
            KajiTheme.accent
        case "R":
            KajiTheme.accent
        case "U":
            KajiTheme.diffAddFg
        default:
            KajiTheme.fgMuted
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            KajiIcon(systemName: expanded ? "chevron.down" : "chevron.right", size: 10)
                .foregroundStyle(KajiTheme.fgDim)
                .frame(width: 12)

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
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(hovered ? KajiTheme.hover : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .animation(KajiMotion.fast, value: expanded)
        .animation(KajiMotion.hover, value: hovered)
        .kajiChangeFeedback(KajiMotion.selectionFeedback, value: expanded, isEnabled: expanded)
        .onTapGesture(perform: onToggle)
    }

    private var actionButtons: some View {
        HStack(spacing: 0) {
            IconButton(symbol: "doc.text", size: 11, accessibilityLabel: "Open in Editor", action: onOpenInEditor)
                .help("Open in Editor")
            IconButton(symbol: "rectangle.split.2x1", size: 11, accessibilityLabel: "Open Diff in New Tab", action: onOpenDiff)
                .help("Open Diff in New Tab")
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
