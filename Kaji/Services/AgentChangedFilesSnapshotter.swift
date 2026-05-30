import Foundation

enum AgentChangedFilesSnapshotter {
    static func snapshot(
        repoPath: String,
        policy: AgentChangedFilesSnapshotPolicy = .default
    ) async -> [AgentChangedFile]? {
        do {
            let files = try await GitRepositoryService().changedFiles(repoPath: repoPath)
            return policy.capturedFiles(from: files.map(map))
        } catch {
            return nil
        }
    }

    private static func map(_ file: GitStatusFile) -> AgentChangedFile {
        AgentChangedFile(
            path: file.path,
            oldPath: file.oldPath,
            status: status(for: file),
            additions: file.additions,
            deletions: file.deletions,
            isBinary: file.isBinary
        )
    }

    private static func status(for file: GitStatusFile) -> AgentChangedFileStatus {
        switch file.statusText {
        case "A":
            file.xStatus == "?" ? .untracked : .added
        case "M":
            .modified
        case "D":
            .deleted
        case "R":
            .renamed
        case "C":
            .copied
        case "U":
            .conflicted
        default:
            .unknown
        }
    }
}
