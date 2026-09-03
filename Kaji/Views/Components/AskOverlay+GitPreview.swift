import Foundation

extension AskOverlay {
    var gitPreviewEntries: [AskPaletteEntry]? {
        guard let state = GitCommandParser.state(for: fieldText) else { return nil }
        let request = GitCommandParser.request(command: state.command, input: state.filter)
        guard GitCommandCatalog.descriptor(for: request.arguments).autoPreviews else { return nil }
        let activeKey = selectedWorktree.map { GitCommandPreviewKey(worktreePath: $0.path, displayCommand: request.displayCommand) }
        switch gitPreviewStatus {
        case let .loading(key) where key == activeKey:
            return placeholder("loading", title: "Loading \(request.displayCommand)", detail: "Reading Git data")
        case let .loaded(result) where result.request == request && result.key == activeKey:
            return gitPreviewEntries(result)
        case let .failed(key, message) where key == activeKey:
            return placeholder("failed", title: "Failed to load \(request.displayCommand)", detail: message)
        default:
            return placeholder("pending", title: "Preparing \(request.displayCommand)", detail: "Reading Git data")
        }
    }

    func refreshGitCommandPreview() {
        guard let state = GitCommandParser.state(for: fieldText),
              let selectedProject,
              let selectedWorktree
        else {
            gitPreviewTask?.cancel()
            gitPreviewTask = nil
            gitPreviewStatus = .idle
            return
        }
        let request = GitCommandParser.request(command: state.command, input: state.filter)
        let descriptor = GitCommandCatalog.descriptor(for: request.arguments)
        guard descriptor.autoPreviews, let presentation = descriptor.presentation else {
            gitPreviewTask?.cancel()
            gitPreviewTask = nil
            gitPreviewStatus = .idle
            return
        }
        let key = GitCommandPreviewKey(worktreePath: selectedWorktree.path, displayCommand: request.displayCommand)
        if case let .loaded(result) = gitPreviewStatus, result.key == key {
            return
        }
        if case let .loading(loadingKey) = gitPreviewStatus, loadingKey == key {
            return
        }
        gitPreviewTask?.cancel()
        gitPreviewStatus = .loading(key)
        gitPreviewTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let result = await GitCommandPreviewLoader.load(
                request: request,
                presentation: presentation,
                projectID: selectedProject.id,
                worktreeID: selectedWorktree.id,
                worktreePath: selectedWorktree.path
            )
            guard !Task.isCancelled else { return }
            gitPreviewStatus = .loaded(result)
            highlightedIndex = entries.isEmpty ? nil : min(highlightedIndex ?? 0, entries.count - 1)
        }
    }

    func gitPreviewEntries(_ result: GitCommandPreviewResult) -> [AskPaletteEntry] {
        switch result.presentation {
        case .commitLog:
            commitEntries(result)
        case .branchList:
            branchEntries(result)
        case .statusList:
            statusEntries(result)
        case .plainOutput:
            outputEntries(result)
        }
    }

    private func commitEntries(_ result: GitCommandPreviewResult) -> [AskPaletteEntry] {
        guard let projectID, let worktreeID else {
            return placeholder("missing-target", title: "No worktree selected", detail: result.request.displayCommand)
        }
        return result.commits.map { commit in
            AskPaletteEntry(
                action: .gitCommitDiff(commit, projectID: projectID, worktreeID: worktreeID, worktreePath: result.key.worktreePath),
                title: commit.subject,
                detail: "\(commit.shortHash) · \(commit.authorName)",
                annotation: "Diff"
            )
        }
    }

    private func branchEntries(_ result: GitCommandPreviewResult) -> [AskPaletteEntry] {
        result.branches.map { branch in
            AskPaletteEntry(
                action: .gitBranch(name: branch, isCurrent: branch == currentGitBranch),
                title: branch,
                detail: branch == currentGitBranch ? "Current branch" : "Local branch",
                annotation: branch == currentGitBranch ? "Current" : "Switch"
            )
        }
    }

    private func statusEntries(_ result: GitCommandPreviewResult) -> [AskPaletteEntry] {
        guard !result.files.isEmpty else {
            return placeholder("clean", title: "No changes", detail: "Working tree is clean")
        }
        let summary = AskPaletteEntry(
            action: .openDiffSummary(
                projectID: result.files[0].projectID,
                worktreeID: result.files[0].worktreeID,
                worktreePath: result.files[0].worktreePath
            ),
            title: "Open all changes",
            detail: "Diff viewer for \(result.files.count) changed file\(result.files.count == 1 ? "" : "s")",
            annotation: "Enter"
        )
        return [summary] + result.files.map { file in
            AskPaletteEntry(
                action: .diffFile(file),
                title: file.file.path,
                detail: "\(file.sectionTitle) • \(file.file.statSummaryText)",
                annotation: file.file.paletteAnnotationText
            )
        }
    }

    private func outputEntries(_ result: GitCommandPreviewResult) -> [AskPaletteEntry] {
        let lines = result.output.split(separator: "\n", omittingEmptySubsequences: false).prefix(120)
        guard !lines.isEmpty else {
            return placeholder("empty", title: "No output", detail: result.request.displayCommand)
        }
        return lines.enumerated().map { index, line in
            AskPaletteEntry(
                action: .gitPreviewPlaceholder("\(index)"),
                title: String(line),
                detail: result.request.displayCommand,
                annotation: nil
            )
        }
    }

    private func placeholder(_ id: String, title: String, detail: String) -> [AskPaletteEntry] {
        [
            .init(
                action: .gitPreviewPlaceholder(id),
                title: title,
                detail: detail,
                annotation: nil
            ),
        ]
    }
}
