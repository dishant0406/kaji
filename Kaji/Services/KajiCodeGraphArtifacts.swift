import Foundation

enum KajiCodeGraphArtifacts {
    static func delete(projectID: UUID, worktreeID: UUID, fileManager: FileManager = .default) throws {
        let directory = KajiCodeGraphDirectory.projectDirectory(projectID: projectID, worktreeID: worktreeID)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }
}
