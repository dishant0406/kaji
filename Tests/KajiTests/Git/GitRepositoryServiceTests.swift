import Foundation
import Testing

@testable import Kaji

struct GitRepositoryServiceTests {
    @Test
    func normalizedBranchNameTrimsValidNames() {
        #expect(GitRepositoryService.normalizedBranchName(" feature/top-bar ") == "feature/top-bar")
    }

    @Test
    func normalizedBranchNameRejectsInvalidNames() {
        #expect(GitRepositoryService.normalizedBranchName("-feature") == nil)
        #expect(GitRepositoryService.normalizedBranchName("feature branch") == nil)
        #expect(GitRepositoryService.normalizedBranchName("") == nil)
    }

    @Test
    func commitFilesAndPatchLoadCommittedChanges() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedRepository(at: directory)
        try "Initial\nNext\n".write(to: directory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], in: directory)
        try runGit(["commit", "-m", "Update readme"], in: directory)
        let hash = try gitOutput(["rev-parse", "HEAD"], in: directory)
        let parent = try gitOutput(["rev-parse", "HEAD~1"], in: directory)

        let service = GitRepositoryService()
        let files = try await service.commitFiles(repoPath: directory.path, hash: hash, parentHash: parent)
        let diff = try await service.commitPatchAndCompare(
            repoPath: directory.path,
            filePath: "README.md",
            source: .commit(hash: hash, parentHash: parent),
            lineLimit: nil,
            contextLineCount: 3
        )

        #expect(files.contains { $0.path == "README.md" && $0.xStatus == "M" })
        #expect(diff.rows.contains { $0.kind == .addition && $0.newText == "Next" })
    }

    @Test
    func commitArgumentsBypassHooks() {
        #expect(GitRepositoryService.commitArguments(message: "Ship") == ["commit", "--no-verify", "-m", "Ship"])
    }

    @Test
    func commitBypassesPreCommitHook() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedRepository(at: directory)
        let hook = directory.appendingPathComponent(".git/hooks/pre-commit")
        try "#!/bin/sh\nexit 1\n".write(to: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        try "Initial\nNext\n".write(to: directory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], in: directory)

        let hash = try await GitRepositoryService().commit(repoPath: directory.path, message: "Update readme")
        let subject = try gitOutput(["log", "-1", "--pretty=%s"], in: directory)

        #expect(!hash.isEmpty)
        #expect(subject == "Update readme")
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

    private func gitOutput(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
