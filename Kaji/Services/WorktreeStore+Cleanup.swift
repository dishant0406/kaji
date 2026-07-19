import Foundation

extension WorktreeStore {
    @discardableResult
    static func cleanupOnDisk(
        worktree: Worktree,
        repoPath: String
    ) async -> Bool {
        guard worktree.canBeRemoved else { return true }
        do {
            try await RiftWorkspaceService.shared.removeWorkspace(at: worktree.path)
            try await RiftWorkspaceService.shared.gc(workingDirectory: repoPath)
            removeParentDirectoryIfEmpty(for: worktree.path)
            return true
        } catch {
            worktreeStoreLogger.error("Failed to remove Rift workspace at \(worktree.path): \(error)")
            do {
                if FileManager.default.fileExists(atPath: worktree.path) {
                    try FileManager.default.removeItem(atPath: worktree.path)
                }
                try? await RiftWorkspaceService.shared.gc(workingDirectory: repoPath)
                removeParentDirectoryIfEmpty(for: worktree.path)
                return true
            } catch {
                worktreeStoreLogger.error("Fallback workspace cleanup failed at \(worktree.path): \(error)")
                return false
            }
        }
    }

    @discardableResult
    static func cleanupOnDisk(for project: Project, knownWorktrees: [Worktree]) async -> Bool {
        var succeeded = true
        for worktree in knownWorktrees.filter(\.canBeRemoved).prefix(128)
            where await !cleanupOnDisk(worktree: worktree, repoPath: project.path)
        {
            succeeded = false
        }

        let root = KajiFileStorage.worktreeRoot(forProjectID: project.id)
        guard FileManager.default.fileExists(atPath: root.path) else { return succeeded }
        do {
            let children = try FileManager.default.contentsOfDirectory(atPath: root.path)
            guard children.count <= 128 else { return false }
            for child in children {
                let childPath = root.appendingPathComponent(child).path
                do {
                    try await RiftWorkspaceService.shared.removeWorkspace(at: childPath)
                } catch {
                    if FileManager.default.fileExists(atPath: childPath) {
                        try FileManager.default.removeItem(atPath: childPath)
                    }
                }
            }
            try? await RiftWorkspaceService.shared.gc(workingDirectory: project.path)
            if FileManager.default.fileExists(atPath: root.path) {
                try FileManager.default.removeItem(at: root)
            }
        } catch {
            worktreeStoreLogger.error("Project workspace cleanup failed at \(root.path): \(error)")
            succeeded = false
        }
        return succeeded
    }

    private static func removeParentDirectoryIfEmpty(for path: String) {
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent()
        let children = (try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? []
        guard children.isEmpty else { return }
        try? FileManager.default.removeItem(at: parent)
    }
}
