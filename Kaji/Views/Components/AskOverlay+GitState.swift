import SwiftUI

extension AskOverlay {
    var isGitCommandMode: Bool {
        GitCommandParser.state(for: fieldText) != nil
    }

    func refreshGitBranches() {
        guard isGitCommandMode,
              let worktreePath = selectedWorktree?.path
        else {
            gitBranchesTask?.cancel()
            gitBranches = []
            currentGitBranch = nil
            isLoadingGitBranches = false
            return
        }

        gitBranchesTask?.cancel()
        isLoadingGitBranches = true
        gitBranchesTask = Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) {
                let git = GitRepositoryService()
                async let branches = try? git.listBranches(repoPath: worktreePath)
                async let branch = try? git.currentBranch(repoPath: worktreePath)
                return await (branches ?? [], branch)
            }.value
            guard !Task.isCancelled else { return }
            gitBranches = result.0
            currentGitBranch = result.1
            isLoadingGitBranches = false
            highlightedIndex = entries.isEmpty ? nil : min(highlightedIndex ?? 0, entries.count - 1)
        }
    }
}
