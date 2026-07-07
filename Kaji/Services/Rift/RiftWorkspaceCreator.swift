import Foundation

struct RiftWorkspaceCreationRequest {
    let project: Project
    let name: String
    let branch: String
    let createBranch: Bool
}

enum RiftWorkspaceCreator {
    static func create(_ request: RiftWorkspaceCreationRequest) async throws -> Worktree {
        let slug = WorktreeNameSlug.slug(from: request.name)
        let createdPath = try await RiftWorkspaceService.shared.createWorkspace(
            from: request.project.path,
            name: slug
        )
        do {
            let branch = try await RiftGitBranchPreparer.prepare(
                repoPath: createdPath,
                branch: request.branch,
                createBranch: request.createBranch
            )
            let riftID = await RiftWorkspaceService.shared.riftID(at: createdPath)
            return Worktree(
                name: request.name,
                path: createdPath,
                branch: branch,
                source: .kaji,
                backend: .rift,
                riftID: riftID,
                isPrimary: false
            )
        } catch {
            try? await RiftWorkspaceService.shared.removeWorkspace(at: createdPath)
            try? await RiftWorkspaceService.shared.gc(workingDirectory: request.project.path)
            throw error
        }
    }
}
