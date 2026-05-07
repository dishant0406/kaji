import Foundation
import Testing

@testable import Droid

struct DroidCodeGraphDocumentTests {
    @Test
    func decodesDroidGraphContract() throws {
        let json = """
        {
          "projectPath": "/tmp/app",
          "builtAt": "2026-05-07T00:00:00Z",
          "nodes": [
            {"id": "a", "label": "AppState", "file_type": "swift", "source_file": "AppState.swift", "community": 1, "degree": 3}
          ],
          "edges": [
            {"source": "a", "target": "b", "relation": "calls", "confidence": "EXTRACTED"}
          ],
          "communities": [
            {"id": 1, "label": "Community 1", "node_count": 1}
          ]
        }
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try json.data(using: .utf8)?.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let document = try DroidCodeGraphDocumentLoader.load(url: url)

        #expect(document.projectPath == "/tmp/app")
        #expect(document.nodes.first?.label == "AppState")
        #expect(document.edges.first?.relation == "calls")
        #expect(document.communities.first?.nodeCount == 1)
        #expect(document.versionID == nil)
        #expect(document.git == nil)
    }

    @Test
    func decodesVersionMetadataWhenPresent() throws {
        let json = """
        {
          "projectPath": "/tmp/app",
          "builtAt": "2026-05-07T00:00:00Z",
          "versionID": "abc123",
          "versionBuiltAt": "2026-05-07T01:00:00Z",
          "git": {
            "commit": "abc123def456",
            "shortCommit": "abc123",
            "branch": "main",
            "isDirty": false
          },
          "nodes": [],
          "edges": [],
          "communities": []
        }
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try json.data(using: .utf8)?.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let document = try DroidCodeGraphDocumentLoader.load(url: url)

        #expect(document.versionID == "abc123")
        #expect(document.versionBuiltAt == "2026-05-07T01:00:00Z")
        #expect(document.git?.shortCommit == "abc123")
        #expect(document.git?.isDirty == false)
    }
}
