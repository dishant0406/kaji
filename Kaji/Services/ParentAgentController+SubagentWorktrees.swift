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
        do {
            let worktree = try await RiftWorkspaceCreator.create(RiftWorkspaceCreationRequest(
                project: project,
                name: name,
                branch: branch,
                createBranch: true
            ))
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
