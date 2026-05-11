import Foundation
import Testing

@testable import Kaji

@Suite("KajiCodeGraphVersionArchive", .serialized)
struct KajiCodeGraphVersionArchiveTests {
    @Test
    func archivesGraphFilesAndAnnotatesMetadata() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        KajiCodeGraphEnvironmentTestLock.lock()
        setenv("KAJI_EXTENSIONS_DIR", root.path, 1)
        defer {
            unsetenv("KAJI_EXTENSIONS_DIR")
            try? fileManager.removeItem(at: root)
            KajiCodeGraphEnvironmentTestLock.unlock()
        }

        let projectID = UUID()
        let worktreeID = UUID()
        let output = KajiCodeGraphDirectory.graphOutputDirectory(projectID: projectID, worktreeID: worktreeID)
        try fileManager.createDirectory(at: output, withIntermediateDirectories: true)
        try writeFixtureFiles(to: output)

        let snapshot = KajiCodeGraphGitSnapshot(
            commit: "abcdef123456",
            shortCommit: "abcdef1",
            branch: "main",
            isDirty: false
        )

        let entry = try KajiCodeGraphVersionArchive.record(
            projectID: projectID,
            worktreeID: worktreeID,
            outputDirectory: output,
            snapshot: snapshot,
            fileManager: fileManager
        )
        let archivedGraph = URL(fileURLWithPath: entry.kajiGraphPath)
        let archivedReport = URL(fileURLWithPath: entry.reportPath)
        let annotated = try JSONSerialization.jsonObject(with: Data(contentsOf: archivedGraph)) as? [String: Any]
        let git = annotated?["git"] as? [String: Any]
        let index = KajiCodeGraphVersionArchive.loadIndex(projectID: projectID, worktreeID: worktreeID)

        #expect(entry.id == "abcdef1")
        #expect(fileManager.fileExists(atPath: archivedReport.path))
        #expect(annotated?["versionID"] as? String == "abcdef1")
        #expect(git?["shortCommit"] as? String == "abcdef1")
        #expect(git?["isDirty"] as? Bool == false)
        #expect(index.first?.id == "abcdef1")
    }

    @Test
    func dirtySnapshotsUseDistinctVersionIDs() {
        let clean = KajiCodeGraphGitSnapshot(commit: nil, shortCommit: "abc123", branch: nil, isDirty: false)
        let dirty = KajiCodeGraphGitSnapshot(commit: nil, shortCommit: "abc123", branch: nil, isDirty: true)

        #expect(clean.versionID == "abc123")
        #expect(dirty.versionID.hasPrefix("abc123-dirty-"))
    }

    private func writeFixtureFiles(to output: URL) throws {
        let graph = """
        {"projectPath":"/tmp/app","builtAt":"2026-05-07T00:00:00Z","nodes":[],"edges":[],"communities":[]}
        """
        try Data(graph.utf8).write(to: output.appendingPathComponent("kaji-graph.json"))
        try Data("{\"ok\":true}".utf8).write(to: output.appendingPathComponent("status.json"))
        try Data("{\"nodes\":[]}".utf8).write(to: output.appendingPathComponent("graph.json"))
        try Data("# Graph\\n".utf8).write(to: output.appendingPathComponent("GRAPH_REPORT.md"))
        try Data("{}".utf8).write(to: output.appendingPathComponent("analysis.json"))
        try Data("{}".utf8).write(to: output.appendingPathComponent("manifest.json"))
    }
}
