import Testing

@testable import Kaji

@Suite("DiagnosticsStore")
@MainActor
struct DiagnosticsStoreTests {
    @Test("groups diagnostics by file and counts severities")
    func groupsDiagnostics() {
        let store = DiagnosticsStore()
        store.setDiagnostics([
            diagnostic(path: "/tmp/A.swift", relative: "A.swift", line: 1, severity: .error),
            diagnostic(path: "/tmp/A.swift", relative: "A.swift", line: 3, severity: .information),
        ], for: "/tmp/A.swift")

        store.setDiagnostics([
            diagnostic(path: "/tmp/B.swift", relative: "B.swift", line: 2, severity: .warning),
        ], for: "/tmp/B.swift")

        #expect(store.errorCount == 1)
        #expect(store.warningCount == 1)
        #expect(store.groups.map(\.relativePath) == ["A.swift", "B.swift"])
        #expect(store.groups[0].diagnostics.map(\.severity) == [.error, .information])
    }

    @Test("clears diagnostics per file")
    func clearsDiagnostics() {
        let store = DiagnosticsStore()
        store.setDiagnostics([
            diagnostic(path: "/tmp/A.swift", relative: "A.swift", line: 1, severity: .error),
        ], for: "/tmp/A.swift")

        store.clearDiagnostics(for: "/tmp/A.swift")

        #expect(store.allDiagnostics.isEmpty)
        #expect(store.groups.isEmpty)
    }

    private func diagnostic(
        path: String,
        relative: String,
        line: Int,
        severity: EditorDiagnosticSeverity
    ) -> EditorDiagnostic {
        EditorDiagnostic(
            id: "\(path):\(line)",
            filePath: path,
            relativePath: relative,
            line: line,
            column: 1,
            severity: severity,
            message: "Problem",
            source: "test"
        )
    }
}
