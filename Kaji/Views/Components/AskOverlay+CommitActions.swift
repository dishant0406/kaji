import Foundation

extension AskOverlay {
    func handleCommitSubmit() -> Bool {
        guard let flow = commitFlow else { return false }
        switch flow.stage {
        case .selectFiles,
             .chooseMessageMode:
            confirmHighlight()
        case .reviewMessage:
            commitSelectedFiles()
        case .result:
            cancelCommitFlow()
        default:
            break
        }
        return true
    }

    func handleCommitShiftSubmit() -> Bool {
        guard let flow = commitFlow else { return false }
        if flow.stage == .selectFiles {
            continueCommitAfterSelection()
        } else {
            _ = handleCommitSubmit()
        }
        return true
    }

    func applyCommitEntry(_ entry: AskPaletteEntry) -> Bool {
        switch entry.action {
        case .gitCommitStart:
            startCommitFlow()
        case .gitCommitSelectAll:
            selectAllCommitFilesAndContinue()
        case let .gitCommitSelectFile(path, _):
            toggleCommitFile(path)
        case let .gitCommitMessageMode(mode):
            beginCommitMessage(mode)
        default:
            return false
        }
        return true
    }

    func selectAllCommitFilesAndContinue() {
        guard var flow = commitFlow else { return }
        flow.selectedPaths = Set(flow.files.map(\.path))
        commitFlow = flow
        continueCommitAfterSelection()
    }

    func toggleCommitFile(_ path: String) {
        guard var flow = commitFlow else { return }
        if flow.selectedPaths.contains(path) {
            flow.selectedPaths.remove(path)
        } else {
            flow.selectedPaths.insert(path)
        }
        commitFlow = flow
    }

    func continueCommitAfterSelection() {
        guard var flow = commitFlow else { return }
        guard flow.hasSelection else {
            flow.errorText = "Select at least one file."
            commitFlow = flow
            return
        }
        flow.errorText = nil
        flow.stage = .chooseMessageMode
        commitFlow = flow
        highlightedIndex = entries.isEmpty ? nil : 0
    }

    func beginCommitMessage(_ mode: GitCommitMessageMode) {
        guard let flow = commitFlow, let worktree = selectedWorktree else { return }
        commitGenerationTask?.cancel()
        commitGenerationTask = Task { @MainActor in
            let inventory = await GitCommitInventoryBuilder.build(
                repoPath: worktree.path,
                files: flow.files,
                selectedPaths: flow.selectedPaths,
                includeSnippets: false
            )
            guard !Task.isCancelled else { return }
            let draft = GitCommitNativeDraft.message(for: inventory)
            updateCommitFlowForMessage(draft: draft, summary: GitCommitNativeDraft.summary(for: inventory))
            if mode == .generate {
                refineCommitMessageFromSelection(nativeDraft: draft)
            }
        }
    }

    func updateCommitFlowForMessage(draft: String, summary: String) {
        guard var flow = commitFlow else { return }
        fieldText = ""
        flow.stage = .reviewMessage
        flow.message = draft
        flow.nativeDraft = draft
        flow.statusText = summary
        flow.errorText = nil
        commitFlow = flow
    }
}
