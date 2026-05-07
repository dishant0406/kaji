import Foundation
import Testing

@testable import Droid

@Suite("DroidCodeGraphVersionArchive", .serialized)
struct DroidCodeGraphVersionArchiveTests {
    @Test
    func archivesGraphFilesAndAnnotatesMetadata() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        setenv("DROID_EXTENSIONS_DIR", root.path, 1)
        defer {
            unsetenv("DROID_EXTENSIONS_DIR")
            try? fileManager.removeItem(at: root)
        }

        let projectID = UUID()
        let worktreeID = UUID()
        let output = DroidCodeGraphDirectory.graphOutputDirectory(projectID: projectID, worktreeID: worktreeID)
        try fileManager.createDirectory(at: output, withIntermediateDirectories: true)
        try writeFixtureFiles(to: output)

        let snapshot = DroidCodeGraphGitSnapshot(
            commit: "abcdef123456",
            shortCommit: "abcdef1",
            branch: "main",
            isDirty: false
        )

        let entry = try DroidCodeGraphVersionArchive.record(
            projectID: projectID,
            worktreeID: worktreeID,
            outputDirectory: output,
            snapshot: snapshot,
            fileManager: fileManager
        )
        let archivedGraph = URL(fileURLWithPath: entry.droidGraphPath)
        let archivedReport = URL(fileURLWithPath: entry.reportPath)
        let annotated = try JSONSerialization.jsonObject(with: Data(contentsOf: archivedGraph)) as? [String: Any]
        let git = annotated?["git"] as? [String: Any]
        let index = DroidCodeGraphVersionArchive.loadIndex(projectID: projectID, worktreeID: worktreeID)

        #expect(entry.id == "abcdef1")
        #expect(fileManager.fileExists(atPath: archivedReport.path))
        #expect(annotated?["versionID"] as? String == "abcdef1")
        #expect(git?["shortCommit"] as? String == "abcdef1")
        #expect(git?["isDirty"] as? Bool == false)
        #expect(index.first?.id == "abcdef1")
    }

    @Test
    func dirtySnapshotsUseDistinctVersionIDs() {
        let clean = DroidCodeGraphGitSnapshot(commit: nil, shortCommit: "abc123", branch: nil, isDirty: false)
        let dirty = DroidCodeGraphGitSnapshot(commit: nil, shortCommit: "abc123", branch: nil, isDirty: true)

        #expect(clean.versionID == "abc123")
        #expect(dirty.versionID.hasPrefix("abc123-dirty-"))
    }

    private func writeFixtureFiles(to output: URL) throws {
        let graph = """
        {"projectPath":"/tmp/app","builtAt":"2026-05-07T00:00:00Z","nodes":[],"edges":[],"communities":[]}
        """
        try Data(graph.utf8).write(to: output.appendingPathComponent("droid-graph.json"))
        try Data("{\"ok\":true}".utf8).write(to: output.appendingPathComponent("status.json"))
        try Data("{\"nodes\":[]}".utf8).write(to: output.appendingPathComponent("graph.json"))
        try Data("# Graph\\n".utf8).write(to: output.appendingPathComponent("GRAPH_REPORT.md"))
        try Data("{}".utf8).write(to: output.appendingPathComponent("analysis.json"))
        try Data("{}".utf8).write(to: output.appendingPathComponent("manifest.json"))
    }
}
