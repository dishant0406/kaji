import Foundation

enum RiftGitBranchPreparer {
    static func prepare(repoPath: String, branch: String, createBranch: Bool) async throws -> String {
        let git = GitRepositoryService()
        if createBranch {
            try await git.createAndSwitchBranch(repoPath: repoPath, name: branch)
        } else {
            try await git.switchBranch(repoPath: repoPath, branch: branch)
        }
        return try await git.currentBranch(repoPath: repoPath)
    }
}
