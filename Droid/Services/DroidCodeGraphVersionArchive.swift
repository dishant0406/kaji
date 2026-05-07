import Foundation

struct DroidCodeGraphVersionEntry: Codable, Equatable {
    let id: String
    let builtAt: String
    let git: DroidCodeGraphGitSnapshot
    let graphPath: String
    let droidGraphPath: String
    let reportPath: String
}

enum DroidCodeGraphVersionArchive {
    static func loadIndex(projectID: UUID, worktreeID: UUID, fileManager _: FileManager = .default) -> [DroidCodeGraphVersionEntry] {
        let url = DroidCodeGraphDirectory.graphVersionsIndex(projectID: projectID, worktreeID: worktreeID)
        guard let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([DroidCodeGraphVersionEntry].self, from: data)
        else { return [] }
        return entries
    }

    static func record(
        projectID: UUID,
        worktreeID: UUID,
        outputDirectory: URL,
        snapshot: DroidCodeGraphGitSnapshot,
        fileManager: FileManager = .default
    ) throws -> DroidCodeGraphVersionEntry {
        let versionID = snapshot.versionID
        let versionDirectory = DroidCodeGraphDirectory.graphVersionDirectory(
            projectID: projectID,
            worktreeID: worktreeID,
            versionID: versionID
        )
        try fileManager.createDirectory(at: versionDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let builtAt = ISO8601DateFormatter().string(from: Date())
        try annotateJSON(
            outputDirectory.appendingPathComponent("droid-graph.json"),
            versionID: versionID,
            builtAt: builtAt,
            snapshot: snapshot
        )
        try annotateJSON(outputDirectory.appendingPathComponent("status.json"), versionID: versionID, builtAt: builtAt, snapshot: snapshot)
        for name in ["graph.json", "droid-graph.json", "GRAPH_REPORT.md", "analysis.json", "manifest.json", "status.json"] {
            try copy(name, from: outputDirectory, to: versionDirectory, fileManager: fileManager)
        }
        let entry = DroidCodeGraphVersionEntry(
            id: versionID,
            builtAt: builtAt,
            git: snapshot,
            graphPath: versionDirectory.appendingPathComponent("graph.json").path,
            droidGraphPath: versionDirectory.appendingPathComponent("droid-graph.json").path,
            reportPath: versionDirectory.appendingPathComponent("GRAPH_REPORT.md").path
        )
        try writeIndex(entry: entry, projectID: projectID, worktreeID: worktreeID, fileManager: fileManager)
        return entry
    }

    private static func annotateJSON(_ url: URL, versionID: String, builtAt: String, snapshot: DroidCodeGraphGitSnapshot) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let data = try Data(contentsOf: url)
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        object["versionID"] = versionID
        object["versionBuiltAt"] = builtAt
        var git: [String: Any] = ["isDirty": snapshot.isDirty]
        if let commit = snapshot.commit { git["commit"] = commit }
        if let shortCommit = snapshot.shortCommit { git["shortCommit"] = shortCommit }
        if let branch = snapshot.branch { git["branch"] = branch }
        object["git"] = git
        let output = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try output.write(to: url, options: .atomic)
    }

    private static func copy(_ name: String, from source: URL, to destination: URL, fileManager: FileManager) throws {
        let sourceURL = source.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: sourceURL.path) else { return }
        let destinationURL = destination.appendingPathComponent(name)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    private static func writeIndex(entry: DroidCodeGraphVersionEntry, projectID: UUID, worktreeID: UUID, fileManager: FileManager) throws {
        let url = DroidCodeGraphDirectory.graphVersionsIndex(projectID: projectID, worktreeID: worktreeID)
        let existing = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([DroidCodeGraphVersionEntry].self, from: $0) } ?? []
        let entries = ([entry] + existing.filter { $0.id != entry.id }).prefix(25)
        let data = try JSONEncoder().encode(Array(entries))
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try data.write(to: url, options: .atomic)
    }
}
