import Foundation

struct KajiCodeGraphGitSnapshot: Codable, Equatable {
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

    static func capture(projectPath: String) async -> KajiCodeGraphGitSnapshot {
        async let commit = git(projectPath: projectPath, arguments: ["rev-parse", "HEAD"])
        async let shortCommit = git(projectPath: projectPath, arguments: ["rev-parse", "--short", "HEAD"])
        async let branch = git(projectPath: projectPath, arguments: ["branch", "--show-current"])
        async let status = git(projectPath: projectPath, arguments: ["status", "--porcelain", "--untracked-files=all"])
        return await KajiCodeGraphGitSnapshot(
            commit: commit,
            shortCommit: shortCommit,
            branch: branch,
            isDirty: hasSourceChanges(status ?? "")
        )
    }

    static func hasSourceChanges(_ status: String) -> Bool {
        status
            .split(separator: "\n")
            .map(String.init)
            .contains { !isIgnoredGeneratedArtifact($0) }
    }

    private static func git(projectPath: String, arguments: [String]) async -> String? {
        guard let result = try? await GitProcessRunner.runGit(repoPath: projectPath, arguments: arguments),
              result.status == 0
        else { return nil }
        let value = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func isIgnoredGeneratedArtifact(_ line: String) -> Bool {
        guard line.count > 3 else { return false }
        let path = String(line.dropFirst(3))
        return path == "graphify-out" ||
            path.hasPrefix("graphify-out/") ||
            path.hasPrefix(".graphify/")
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }
}
