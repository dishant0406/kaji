enum CreateWorktreeResult {
    case created(Worktree, runSetup: Bool)
    case cancelled
}
