import Foundation
import Testing

@testable import Kaji

@Suite("File search")
struct FileSearchServiceTests {
    @Test("filename matches outrank path-only matches")
    func filenameMatchesOutrankPathMatches() {
        let candidates = [
            makeResult("Sources/PaletteOverlay.swift"),
            makeResult("Docs/notes/command-palette.md"),
            makeResult("Views/QuickOpen/OverlayNotes.txt"),
        ]

        let ranked = FileSearchRanker.rankCandidates(candidates, query: "palette", maxResults: 30)

        #expect(ranked.first?.relativePath == "Sources/PaletteOverlay.swift")
    }

    @Test("path queries prefer directory context")
    func pathQueriesPreferDirectoryContext() {
        let candidates = [
            makeResult("Views/Components/QuickOpenOverlay.swift"),
            makeResult("Docs/quick-open-overlay.md"),
        ]

        let ranked = FileSearchRanker.rankCandidates(candidates, query: "views/quick", maxResults: 30)

        #expect(ranked.first?.relativePath == "Views/Components/QuickOpenOverlay.swift")
    }

    @Test("service finds deep files through FFF")
    func serviceFindsDeepFilesThroughFFF() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let deepFileURL = rootURL
            .appendingPathComponent("a", isDirectory: true)
            .appendingPathComponent("b", isDirectory: true)
            .appendingPathComponent("c", isDirectory: true)
            .appendingPathComponent("d", isDirectory: true)
            .appendingPathComponent("e", isDirectory: true)
            .appendingPathComponent("deep-file.swift")
        try FileManager.default.createDirectory(at: deepFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: deepFileURL)

        let deepResults = await FileSearchService.search(query: "deep", in: rootURL.path)

        #expect(deepResults.contains { $0.absolutePath == deepFileURL.path })
    }

    @Test("FFF binary store selects a dylib install path")
    func fffBinaryStoreSelectsDylibPath() throws {
        let directory = try FFFSearchBinaryStore.installDirectory()

        #expect(directory.path.contains("Search/FFF"))
        #expect(try FFFSearchBinaryStore.libraryURL().lastPathComponent == "libfff_c.dylib")
    }

    @Test("index evicts least recently used project caches")
    func indexEvictsLeastRecentlyUsedProjectCaches() async throws {
        let roots = try (0 ..< 3).map { index in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data().write(to: url.appendingPathComponent("file-\(index).swift"))
            return url
        }
        defer { roots.forEach { try? FileManager.default.removeItem(at: $0) } }

        let index = FileSearchIndex(cacheLifetime: 300, maxCachedProjects: 2, maxFilesPerProject: 100)

        await index.warm(projectPath: roots[0].path)
        await index.warm(projectPath: roots[1].path)
        _ = await index.cachedFiles(in: roots[0].path)
        await index.warm(projectPath: roots[2].path)

        #expect(await index.cachedFiles(in: roots[0].path) != nil)
        #expect(await index.cachedFiles(in: roots[1].path) == nil)
        #expect(await index.cachedFiles(in: roots[2].path) != nil)
    }

    @Test("index caps files cached per project")
    func indexCapsFilesCachedPerProject() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        for index in 0 ..< 6 {
            try Data().write(to: rootURL.appendingPathComponent("file-\(index).swift"))
        }

        let index = FileSearchIndex(cacheLifetime: 300, maxCachedProjects: 2, maxFilesPerProject: 3)
        let files = await index.files(in: rootURL.path)

        #expect(files.count <= 3)
    }

    @Test("index respects repository gitignore")
    func indexRespectsRepositoryGitignore() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try runGit(["init"], in: rootURL)
        try "node_modules/\n".write(to: rootURL.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try writeData(to: rootURL.appendingPathComponent("Sources/App.swift"))
        try writeData(to: rootURL.appendingPathComponent("node_modules/pkg/index.js"))

        let index = FileSearchIndex(cacheLifetime: 300, maxCachedProjects: 2, maxFilesPerProject: 100)
        let files = await index.files(in: rootURL.path)

        #expect(files.contains { $0.relativePath == "Sources/App.swift" })
        #expect(!files.contains { $0.relativePath == "node_modules/pkg/index.js" })
    }

    private func writeData(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url)
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

    private func makeResult(_ relativePath: String) -> FileSearchResult {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        return FileSearchResult(
            id: relativePath,
            relativePath: relativePath,
            absolutePath: "/tmp/\(relativePath)",
            fileName: fileName
        )
    }
}
