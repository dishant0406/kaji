import Foundation
import Testing

@testable import Droid

struct AgentChangedFilesSnapshotterTests {
    @Test
    func snapshotIncludesModifiedFiles() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedRepository(at: directory)
        try "Hello world\n".write(to: directory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let files = await AgentChangedFilesSnapshotter.snapshot(repoPath: directory.path)

        #expect(files?.contains { $0.path == "README.md" && $0.status == .modified } == true)
    }

    private func seedRepository(at directory: URL) throws {
        try runGit(["init"], in: directory)
        try runGit(["config", "user.email", "test@example.com"], in: directory)
        try runGit(["config", "user.name", "Test User"], in: directory)
        try "Initial\n".write(to: directory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], in: directory)
        try runGit(["commit", "-m", "Initial commit"], in: directory)
    }

    private func runGit(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}
