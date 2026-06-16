import Testing

@testable import Kaji

@Suite("Monaco mappers", .serialized)
@MainActor
struct MonacoMapperTests {
    @Test("maps common file languages")
    func mapsLanguages() {
        #expect(MonacoLanguageMapper.languageID(for: "/tmp/App.swift") == "swift")
        #expect(MonacoLanguageMapper.languageID(for: "/tmp/index.tsx") == "typescript")
        #expect(MonacoLanguageMapper.languageID(for: "/tmp/package.json") == "json")
        #expect(MonacoLanguageMapper.languageID(for: "/tmp/Dockerfile") == "dockerfile")
        #expect(MonacoLanguageMapper.languageID(for: "/tmp/unknown.custom") == "plaintext")
    }

    @Test("maps diagnostics to Monaco markers")
    func mapsDiagnostics() throws {
        let markers = MonacoMarkerMapper.markers(for: [
            EditorDiagnostic(
                id: "a",
                filePath: "/tmp/a.swift",
                relativePath: "a.swift",
                line: 4,
                column: 7,
                severity: .warning,
                message: "careful",
                source: "test"
            ),
        ])
        #expect(markers.count == 1)
        guard case let .object(marker) = markers[0] else {
            Issue.record("Expected object marker")
            return
        }
        #expect(marker["startLineNumber"] == .int(4))
        #expect(marker["startColumn"] == .int(7))
        #expect(marker["endColumn"] == .int(8))
        #expect(marker["severity"] == .string("warning"))
        #expect(marker["message"] == .string("careful"))
    }
}
