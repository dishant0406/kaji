import Foundation
import Testing

@testable import Kaji

@Suite("RiftWorkspaceService")
struct RiftWorkspaceServiceTests {
    @Test("Rift creates a Git workspace that preserves dirty and ignored files")
    func riftCreatesGitWorkspace() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = root.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try run("git", ["init"], in: repo.path)
        try run("git", ["config", "user.email", "test@example.com"], in: repo.path)
        try run("git", ["config", "user.name", "Test"], in: repo.path)
        try "build/\n".write(to: repo.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try "hello\n".write(to: repo.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        try run("git", ["add", "."], in: repo.path)
        try run("git", ["commit", "-m", "initial"], in: repo.path)
        try "changed\n".write(to: repo.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        try run("git", ["add", "file.txt"], in: repo.path)
        try "new\n".write(to: repo.appendingPathComponent("untracked.txt"), atomically: true, encoding: .utf8)
        let build = repo.appendingPathComponent("build", isDirectory: true)
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        try "artifact\n".write(to: build.appendingPathComponent("out.txt"), atomically: true, encoding: .utf8)

        let service = RiftWorkspaceService(databaseURL: root.appendingPathComponent("rift.sqlite"))
        let created = try await service.createWorkspace(
            from: repo.path,
            name: "child",
            into: root.appendingPathComponent("rifts", isDirectory: true).path
        )
        let branch = try await RiftGitBranchPreparer.prepare(repoPath: created, branch: "kaji-test", createBranch: true)
        let records = try await service.listWorkspaces(of: repo.path)

        #expect(branch == "kaji-test")
        #expect(FileManager.default.fileExists(atPath: URL(fileURLWithPath: created).appendingPathComponent(".rift").path))
        #expect(FileManager.default.fileExists(atPath: URL(fileURLWithPath: created).appendingPathComponent("untracked.txt").path))
        #expect(FileManager.default.fileExists(atPath: URL(fileURLWithPath: created).appendingPathComponent("build/out.txt").path))
        #expect(records.contains(where: { $0.path == created && $0.riftID != nil }))
    }
}

private func temporaryDirectory() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("kaji-rift-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@discardableResult
private func run(_ executable: String, _ arguments: [String], in directory: String) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [executable] + arguments
    process.currentDirectoryURL = URL(fileURLWithPath: directory, isDirectory: true)
    let output = Pipe()
    let error = Pipe()
    process.standardOutput = output
    process.standardError = error
    try process.run()
    process.waitUntilExit()
    let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    guard process.terminationStatus == 0 else {
        throw RiftWorkspaceError.commandFailed(stderr.isEmpty ? stdout : stderr)
    }
    return stdout
}
