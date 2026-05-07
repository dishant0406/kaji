import Foundation

enum DroidCodeGraphArtifacts {
    static func delete(projectID: UUID, worktreeID: UUID, fileManager: FileManager = .default) throws {
        let directory = DroidCodeGraphDirectory.projectDirectory(projectID: projectID, worktreeID: worktreeID)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }
}
