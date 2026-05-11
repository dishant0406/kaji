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

    @Test("service finds deep and hidden files")
    func serviceFindsDeepAndHiddenFiles() async throws {
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

        let hiddenFileURL = rootURL.appendingPathComponent(".env")
        try Data().write(to: hiddenFileURL)

        let deepResults = await FileSearchService.search(query: "deep", in: rootURL.path)
        let hiddenResults = await FileSearchService.search(query: ".env", in: rootURL.path)

        #expect(deepResults.contains { $0.absolutePath == deepFileURL.path })
        #expect(hiddenResults.contains { $0.absolutePath == hiddenFileURL.path })
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
