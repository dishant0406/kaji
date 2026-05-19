import Foundation
import Testing

@testable import Kaji

@Suite("Project text search")
struct ProjectTextSearchServiceTests {
    @Test("groups matches by file and sorts locations")
    func groupsMatchesByFile() {
        let matches = [
            ProjectTextSearchMatch(
                id: "/tmp/b.swift:3:1",
                filePath: "/tmp/b.swift",
                relativePath: "b.swift",
                line: 3,
                column: 1,
                preview: "beta"
            ),
            ProjectTextSearchMatch(
                id: "/tmp/a.swift:2:9",
                filePath: "/tmp/a.swift",
                relativePath: "a.swift",
                line: 2,
                column: 9,
                preview: "alpha"
            ),
            ProjectTextSearchMatch(
                id: "/tmp/a.swift:1:4",
                filePath: "/tmp/a.swift",
                relativePath: "a.swift",
                line: 1,
                column: 4,
                preview: "alpha"
            ),
        ]

        let groups = ProjectTextSearchService.group(matches)

        #expect(groups.map(\.relativePath) == ["a.swift", "b.swift"])
        #expect(groups[0].matches.map(\.line) == [1, 2])
    }

    @Test("replace preview counts files and matches")
    func replacePreviewCounts() {
        let groups = [
            ProjectTextSearchFileGroup(
                id: "/tmp/a.swift",
                filePath: "/tmp/a.swift",
                relativePath: "a.swift",
                matches: [
                    ProjectTextSearchMatch(id: "1", filePath: "/tmp/a.swift", relativePath: "a.swift", line: 1, column: 1, preview: "a"),
                    ProjectTextSearchMatch(id: "2", filePath: "/tmp/a.swift", relativePath: "a.swift", line: 2, column: 1, preview: "a"),
                ]
            ),
            ProjectTextSearchFileGroup(
                id: "/tmp/b.swift",
                filePath: "/tmp/b.swift",
                relativePath: "b.swift",
                matches: [
                    ProjectTextSearchMatch(id: "3", filePath: "/tmp/b.swift", relativePath: "b.swift", line: 1, column: 1, preview: "b"),
                ]
            ),
        ]

        let preview = ProjectTextReplacePreview.make(groups: groups, replacement: "new")

        #expect(preview.fileCount == 2)
        #expect(preview.matchCount == 3)
        #expect(preview.replacement == "new")
    }

    @Test("parser reads ripgrep line column output")
    func parserReadsRipgrepOutput() {
        let parser = ProjectTextSearchResultParser(projectPath: "/tmp/project", limit: 10)

        _ = parser.append(chunk: "Sources/App.swift:12:4:let value = needle\n")
        let matches = parser.take()

        #expect(matches.count == 1)
        #expect(matches[0].relativePath == "Sources/App.swift")
        #expect(matches[0].filePath == "/tmp/project/Sources/App.swift")
        #expect(matches[0].line == 12)
        #expect(matches[0].column == 4)
        #expect(matches[0].preview == "let value = needle")
    }

    @Test("replace updates all searched matches")
    func replaceUpdatesMatches() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileURL = rootURL.appendingPathComponent("App.swift")
        try "needle here\nneedle there".write(to: fileURL, atomically: true, encoding: .utf8)
        let groups = [
            ProjectTextSearchFileGroup(
                id: fileURL.path,
                filePath: fileURL.path,
                relativePath: "App.swift",
                matches: [
                    ProjectTextSearchMatch(
                        id: "\(fileURL.path):1:1",
                        filePath: fileURL.path,
                        relativePath: "App.swift",
                        line: 1,
                        column: 1,
                        preview: "needle here"
                    ),
                    ProjectTextSearchMatch(
                        id: "\(fileURL.path):2:1",
                        filePath: fileURL.path,
                        relativePath: "App.swift",
                        line: 2,
                        column: 1,
                        preview: "needle there"
                    ),
                ]
            ),
        ]

        let changed = try await ProjectTextSearchService.replace(query: "needle", groups: groups, with: "thread")

        #expect(changed == [fileURL.path])
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "thread here\nthread there")
    }
}
