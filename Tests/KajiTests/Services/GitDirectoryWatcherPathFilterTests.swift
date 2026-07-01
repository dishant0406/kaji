import Foundation
import Testing

@testable import Kaji

struct GitDirectoryWatcherPathFilterTests {
    @Test
    func shippedCatalogFiltersGeneratedAndVendorDirectories() {
        #expect(GitDirectoryWatcherPathFilter.shouldIgnore(path: "/repo/node_modules/pkg/index.js"))
        #expect(GitDirectoryWatcherPathFilter.shouldIgnore(path: "/repo/.next/server/app.js"))
        #expect(GitDirectoryWatcherPathFilter.shouldIgnore(path: "/repo/.build/debug/Kaji"))
        #expect(GitDirectoryWatcherPathFilter.shouldIgnore(path: "/repo/DerivedData/Build/file.o"))
    }

    @Test
    func shippedCatalogKeepsSourceFiles() {
        #expect(!GitDirectoryWatcherPathFilter.shouldIgnore(path: "/repo/Kaji/Services/GitDirectoryWatcher.swift"))
        #expect(!GitDirectoryWatcherPathFilter.shouldIgnore(path: "/repo/docs/architecture.md"))
    }

    @Test
    func repositoryRulesOverrideShippedCatalog() throws {
        let repo = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }
        try runGit(["init"], in: repo)
        try "custom-output/\n".write(to: repo.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try write("x", to: repo.appendingPathComponent("custom-output/log.txt"))
        try write("x", to: repo.appendingPathComponent("Sources/App.swift"))

        let filter = GitDirectoryWatcherPathFilter(repoPath: repo.path)
        let paths = [
            repo.appendingPathComponent("custom-output/log.txt").path,
            repo.appendingPathComponent("Sources/App.swift").path,
        ]

        #expect(filter.relevantPaths(from: paths) == [repo.appendingPathComponent("Sources/App.swift").path])
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
