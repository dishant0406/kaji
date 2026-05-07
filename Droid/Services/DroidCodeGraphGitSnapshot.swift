import Foundation

struct DroidCodeGraphGitSnapshot: Codable, Equatable {
    let commit: String?
    let shortCommit: String?
    let branch: String?
    let isDirty: Bool

    var versionID: String {
        let base = shortCommit ?? "no-git"
        if isDirty {
            return "\(base)-dirty-\(Self.timestamp())"
        }
        return base
    }

    static func capture(projectPath: String) async -> DroidCodeGraphGitSnapshot {
        async let commit = git(projectPath: projectPath, arguments: ["rev-parse", "HEAD"])
        async let shortCommit = git(projectPath: projectPath, arguments: ["rev-parse", "--short", "HEAD"])
        async let branch = git(projectPath: projectPath, arguments: ["branch", "--show-current"])
        async let status = git(projectPath: projectPath, arguments: ["status", "--porcelain"])
        return await DroidCodeGraphGitSnapshot(
            commit: commit,
            shortCommit: shortCommit,
            branch: branch,
            isDirty: !(status ?? "").isEmpty
        )
    }

    private static func git(projectPath: String, arguments: [String]) async -> String? {
        guard let result = try? await GitProcessRunner.runGit(repoPath: projectPath, arguments: arguments),
              result.status == 0
        else { return nil }
        let value = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }
}
