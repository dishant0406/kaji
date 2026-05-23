import Foundation

@MainActor
@Observable
final class TopBarBranchState {
    var currentBranch: String?
    var branches: [String] = []
    var isLoading = false
    var isSwitching = false

    @ObservationIgnored private let git = GitRepositoryService()
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var activePath: String?

    deinit {
        loadTask?.cancel()
    }

    func refresh(repoPath: String?) {
        guard let repoPath else {
            activePath = nil
            currentBranch = nil
            branches = []
            isLoading = false
            return
        }
        guard repoPath != activePath || branches.isEmpty else { return }
        activePath = repoPath
        load(repoPath: repoPath)
    }

    func reload() {
        guard let activePath else { return }
        load(repoPath: activePath)
    }

    func switchBranch(_ branch: String) {
        guard let activePath, branch != currentBranch, !isSwitching else { return }
        isSwitching = true
        Task { [weak self] in
            guard let self else { return }
            defer { isSwitching = false }
            do {
                try await git.switchBranch(repoPath: activePath, branch: branch)
                guard !Task.isCancelled else { return }
                currentBranch = branch
                ToastState.shared.show("Switched to \(branch)")
                NotificationCenter.default.post(name: .vcsRepoDidChange, object: nil, userInfo: ["repoPath": activePath])
                load(repoPath: activePath)
            } catch {
                guard !Task.isCancelled else { return }
                ToastState.shared.show("Branch switch failed: \(errorText(error))")
            }
        }
    }

    func createAndSwitchBranch(_ branch: String) {
        guard let activePath,
              let branch = GitRepositoryService.normalizedBranchName(branch),
              branch != currentBranch,
              !branches.contains(branch),
              !isSwitching
        else { return }
        isSwitching = true
        Task { [weak self] in
            guard let self else { return }
            defer { isSwitching = false }
            do {
                try await git.createAndSwitchBranch(repoPath: activePath, name: branch)
                guard !Task.isCancelled else { return }
                currentBranch = branch
                ToastState.shared.show("Created and switched to \(branch)")
                NotificationCenter.default.post(name: .vcsRepoDidChange, object: nil, userInfo: ["repoPath": activePath])
                load(repoPath: activePath)
            } catch {
                guard !Task.isCancelled else { return }
                ToastState.shared.show("Branch creation failed: \(errorText(error))")
            }
        }
    }

    private func load(repoPath: String) {
        loadTask?.cancel()
        isLoading = true
        loadTask = Task { [weak self] in
            guard let self else { return }
            defer { isLoading = false }
            let result = await Task.detached(priority: .userInitiated) {
                let git = GitRepositoryService()
                async let branches = try? git.listBranches(repoPath: repoPath)
                async let branch = try? git.currentBranch(repoPath: repoPath)
                return await (branches ?? [], branch)
            }.value
            guard !Task.isCancelled, activePath == repoPath else { return }
            branches = result.0
            currentBranch = result.1
        }
    }

    private func errorText(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
