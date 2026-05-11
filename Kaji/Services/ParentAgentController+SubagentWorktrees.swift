import Foundation

@MainActor
extension ParentAgentController {
    func createIsolatedSubagentWorktree(
        title: String,
        project: Project,
        worktreeStore: WorktreeStore
    ) async -> Worktree? {
        let suffix = String(UUID().uuidString.prefix(8)).lowercased()
        let name = "agent-\(worktreeSlug(from: title))-\(suffix)"
        let branch = "kaji-agent-\(suffix)"
        let path = KajiFileStorage.worktreeDirectory(forProjectID: project.id, name: worktreeSlug(from: name))
            .path(percentEncoded: false)
        guard !FileManager.default.fileExists(atPath: path) else { return nil }
        do {
            try await GitWorktreeService.shared.addWorktree(repoPath: project.path, path: path, branch: branch, createBranch: true)
            let worktree = Worktree(name: name, path: path, branch: branch, ownsBranch: true, isPrimary: false)
            worktreeStore.add(worktree, to: project.id)
            return worktree
        } catch {
            return nil
        }
    }
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
