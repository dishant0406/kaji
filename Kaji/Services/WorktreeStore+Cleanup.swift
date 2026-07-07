import Foundation

extension WorktreeStore {
    static func cleanupOnDisk(
        worktree: Worktree,
        repoPath: String
    ) async {
        guard worktree.canBeRemoved else { return }
        do {
            try await RiftWorkspaceService.shared.removeWorkspace(at: worktree.path)
            try await RiftWorkspaceService.shared.gc(workingDirectory: repoPath)
        } catch {
            worktreeStoreLogger.error("Failed to remove Rift workspace at \(worktree.path): \(error)")
            try? FileManager.default.removeItem(atPath: worktree.path)
            try? await RiftWorkspaceService.shared.gc(workingDirectory: repoPath)
        }
        removeParentDirectoryIfEmpty(for: worktree.path)
    }

    static func cleanupOnDisk(for project: Project, knownWorktrees: [Worktree]) async {
        let secondaryWorktrees = knownWorktrees.filter(\.canBeRemoved)
        for worktree in secondaryWorktrees {
            await cleanupOnDisk(worktree: worktree, repoPath: project.path)
        }

        let root = KajiFileStorage.worktreeRoot(forProjectID: project.id)
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        let children = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        for child in children {
            let childPath = root.appendingPathComponent(child).path
            try? await RiftWorkspaceService.shared.removeWorkspace(at: childPath)
            try? FileManager.default.removeItem(atPath: childPath)
        }
        try? await RiftWorkspaceService.shared.gc(workingDirectory: project.path)
        try? FileManager.default.removeItem(at: root)
    }

    private static func removeParentDirectoryIfEmpty(for path: String) {
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent()
        let children = (try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? []
        guard children.isEmpty else { return }
        try? FileManager.default.removeItem(at: parent)
    }
}
