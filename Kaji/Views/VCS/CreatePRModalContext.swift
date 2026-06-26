struct CreatePRModalContext {
    let currentBranch: String
    let defaultBranch: String?
    let availableBaseBranches: [String]
    let isLoadingBranches: Bool
    let githubAccounts: [GitHubAccount]
    let isLoadingGitHubAccounts: Bool
    let hasStagedChanges: Bool
    let hasUnstagedChanges: Bool
}
