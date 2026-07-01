import Foundation
import Testing

@testable import Kaji

struct GitIgnoreCheckerTests {
    @Test
    func usesRepositoryIgnoreRules() throws {
        let repo = try temporaryRepository()
        defer { try? FileManager.default.removeItem(at: repo) }
        try write("ignored/\n", to: repo.appendingPathComponent(".gitignore"))
        try write("nested-cache/\n", to: repo.appendingPathComponent("Sources/.gitignore"))
        try write("x", to: repo.appendingPathComponent("ignored/file.txt"))
        try write("x", to: repo.appendingPathComponent("Sources/nested-cache/file.txt"))
        try write("x", to: repo.appendingPathComponent("Sources/App.swift"))

        let ignored = try #require(GitIgnoreChecker.ignoredPathsSync(
            repoPath: repo.path,
            relativePaths: ["ignored/file.txt", "Sources/nested-cache/file.txt", "Sources/App.swift"]
        ))

        #expect(ignored == ["ignored/file.txt", "Sources/nested-cache/file.txt"])
    }

    @Test
    func trackedFilesAreNotDroppedByIgnoreRules() throws {
        let repo = try temporaryRepository()
        defer { try? FileManager.default.removeItem(at: repo) }
        try write("ignored/\n", to: repo.appendingPathComponent(".gitignore"))
        try write("x", to: repo.appendingPathComponent("ignored/tracked.txt"))
        try runGit(["add", "-f", "ignored/tracked.txt", ".gitignore"], in: repo)

        let ignored = try #require(GitIgnoreChecker.ignoredPathsSync(
            repoPath: repo.path,
            relativePaths: ["ignored/tracked.txt"]
        ))

        #expect(ignored.isEmpty)
    }

    private func temporaryRepository() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try runGit(["init"], in: directory)
        return directory
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
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
