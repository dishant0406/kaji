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

    @Test("maps Monaco diagnostics to editor diagnostics")
    func mapsDiagnostics() throws {
        let diagnostics = MonacoDiagnosticMapper.diagnostics(
            for: [
                MonacoDiagnosticMarker(
                    startLineNumber: 4,
                    startColumn: 7,
                    endLineNumber: 4,
                    endColumn: 12,
                    severity: 4,
                    message: "careful",
                    source: "typescript"
                ),
            ],
            filePath: "/tmp/project/Sources/App.ts",
            projectPath: "/tmp/project"
        )

        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].relativePath == "Sources/App.ts")
        #expect(diagnostics[0].line == 4)
        #expect(diagnostics[0].column == 7)
        #expect(diagnostics[0].severity == .warning)
        #expect(diagnostics[0].message == "careful")
        #expect(diagnostics[0].source == "typescript")
    }

    @Test("maps language display names")
    func mapsLanguageDisplayNames() {
        #expect(MonacoLanguageMapper.displayName(for: "/tmp/App.swift") == "Swift")
        #expect(MonacoLanguageMapper.displayName(for: "/tmp/index.tsx") == "TypeScript")
        #expect(MonacoLanguageMapper.displayName(for: "/tmp/unknown.custom") == "Plain Text")
    }
}
