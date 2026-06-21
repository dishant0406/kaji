import Foundation

extension AskOverlay {
    func updateCommitMessage(_ message: String) {
        commitFlow?.message = message
    }

    func regenerateCommitMessage() {
        guard let flow = commitFlow else { return }
        refineCommitMessageFromSelection(nativeDraft: flow.nativeDraft.isEmpty ? flow.message : flow.nativeDraft)
    }

    func refineCommitMessageFromSelection(nativeDraft: String) {
        guard let flow = commitFlow, let worktree = selectedWorktree else { return }
        commitGenerationTask?.cancel()
        commitFlow?.isGenerating = true
        commitFlow?.generationText = nil
        let settings = GitCommitMessageSettingsStore.shared.snapshot()
        commitGenerationTask = Task { @MainActor in
            let inventory = await GitCommitInventoryBuilder.build(
                repoPath: worktree.path,
                files: flow.files,
                selectedPaths: flow.selectedPaths,
                snippetPolicy: settings.contextLevel.snippetPolicy
            )
            guard !Task.isCancelled else { return }
            refineCommitMessage(inventory: inventory, nativeDraft: nativeDraft, settings: settings)
        }
    }

    func refineCommitMessage(
        inventory: GitCommitInventory,
        nativeDraft: String,
        settings: GitCommitMessageSettingsSnapshot
    ) {
        guard GitCommitMessageAgent.isAvailable(settings: settings), let selectedProject, let selectedWorktree else {
            commitFlow?.isGenerating = false
            commitFlow?.generationText = GitCommitMessageAgent.unavailableReason(settings: settings)
            return
        }
        commitGenerationTask?.cancel()
        commitFlow?.isGenerating = true
        commitFlow?.generationText = nil
        let request = GitCommitMessageAgentRequest(
            projectName: selectedProject.name,
            repoPath: selectedWorktree.path,
            inventory: inventory,
            nativeDraft: nativeDraft,
            settings: settings
        )
        commitGenerationTask = Task { @MainActor in
            do {
                let result = try await GitCommitMessageAgent.generate(
                    request,
                    appState: appState,
                    projectStore: projectStore,
                    worktreeStore: worktreeStore
                )
                guard !Task.isCancelled else { return }
                commitFlow?.message = result.message
                commitFlow?.generatedMessage = result.message
                commitFlow?.generationText = "Refined with \(result.modelLabel ?? settings.modelLabel) · \(settings.contextLevel.title)"
                commitFlow?.isGenerating = false
            } catch {
                guard !Task.isCancelled else { return }
                commitFlow?.generationText = error.localizedDescription
                commitFlow?.isGenerating = false
            }
        }
    }

    func commitSelectedFiles() {
        guard let flow = commitFlow, let worktree = selectedWorktree else { return }
        let message = flow.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            commitFlow?.errorText = "Enter a commit message."
            return
        }
        commitTask?.cancel()
        commitGenerationTask?.cancel()
        commitFlow?.stage = .committing
        commitFlow?.errorText = nil
        let paths = Array(flow.selectedPaths)
        let allSelected = flow.selectedPaths.count == flow.files.count
        let repoPath = worktree.path
        commitTask = Task { @MainActor in
            do {
                let git = GitRepositoryService()
                if allSelected {
                    try await git.stageAll(repoPath: repoPath)
                } else {
                    try await git.stageFiles(repoPath: repoPath, paths: paths)
                }
                let hash = try await git.commit(repoPath: repoPath, message: message)
                guard !Task.isCancelled else { return }
                commitFlow?.stage = .result
                commitFlow?.committedHash = hash
                commitFlow?.statusText = "Committed \(hash)"
                NotificationCenter.default.post(name: .vcsRepoDidChange, object: nil, userInfo: ["repoPath": repoPath])
            } catch {
                guard !Task.isCancelled else { return }
                commitFlow?.stage = .result
                commitFlow?.errorText = error.localizedDescription
            }
        }
    }

    func cancelCommitFlow() {
        commitFilesTask?.cancel()
        commitGenerationTask?.cancel()
        commitTask?.cancel()
        commitFlow = nil
        fieldText = ""
        highlightedIndex = entries.isEmpty ? nil : 0
    }
}
