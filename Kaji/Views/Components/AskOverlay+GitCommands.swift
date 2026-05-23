import Foundation

extension AskOverlay {
    func runGitCommand(_ request: GitCommandRequest) {
        guard let worktree = selectedWorktree else { return }
        if let message = request.blockedMessage {
            nativeCommandRunner.showMessage(
                title: request.displayCommand,
                message: message,
                workingDirectory: URL(fileURLWithPath: worktree.path)
            )
            return
        }
        if request.confirmationMessage != nil {
            pendingGitCommand = request
            return
        }
        startGitCommand(request, worktreePath: worktree.path)
    }

    func confirmPendingGitCommand() {
        guard let request = pendingGitCommand, let worktree = selectedWorktree else { return }
        pendingGitCommand = nil
        startGitCommand(request, worktreePath: worktree.path)
    }

    func cancelPendingGitCommand() {
        pendingGitCommand = nil
    }

    func startGitCommand(_ request: GitCommandRequest, worktreePath: String) {
        nativeCommandRunner.run(NativeCommandRunPlan(
            title: request.displayCommand,
            executable: "/usr/bin/env",
            arguments: ["git"] + request.arguments,
            workingDirectory: URL(fileURLWithPath: worktreePath),
            refreshesRepository: request.refreshesRepository
        ))
    }

    func stopNativeCommandRun() {
        nativeCommandRunner.stop()
    }

    func finishNativeCommandRun() {
        nativeCommandRunner.close()
    }

    func handleNativeCommandStatus(_ status: NativeCommandRunStatus) {
        guard case .succeeded = status,
              nativeCommandRunner.plan?.refreshesRepository == true,
              let repoPath = nativeCommandRunner.plan?.workingDirectory.path
        else { return }
        NotificationCenter.default.post(name: .vcsRepoDidChange, object: nil, userInfo: ["repoPath": repoPath])
        refreshGitBranches()
    }
}
