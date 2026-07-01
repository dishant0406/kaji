import Foundation
import Testing
@testable import Kaji

struct CodexSessionFileScannerTests {
    @Test
    func selectorKeepsMostRecentFilesWithStableTieBreak() {
        let old = Date(timeIntervalSince1970: 10)
        let new = Date(timeIntervalSince1970: 20)
        let selected = CodexSessionFileSelector.selectRecentPaths(
            from: [
                CodexSessionFileRecord(path: "/tmp/c.jsonl", modifiedAt: old),
                CodexSessionFileRecord(path: "/tmp/b.jsonl", modifiedAt: new),
                CodexSessionFileRecord(path: "/tmp/a.jsonl", modifiedAt: new),
            ],
            limit: 2
        )

        #expect(selected == ["/tmp/a.jsonl", "/tmp/b.jsonl"])
    }

    @Test
    func scannerIgnoresNonJSONLFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexSessionFileScannerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let session = root.appendingPathComponent("session.jsonl")
        let note = root.appendingPathComponent("note.txt")
        FileManager.default.createFile(atPath: session.path, contents: Data())
        FileManager.default.createFile(atPath: note.path, contents: Data())

        let files = CodexSessionFileScanner().recentSessionFiles(rootURL: root, limit: 10)

        #expect(files.map(\.standardizedFileURL) == [session.standardizedFileURL])
    }
}
