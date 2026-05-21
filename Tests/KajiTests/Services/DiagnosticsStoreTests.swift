import Foundation
import Testing
@testable import Kaji

@MainActor
struct DiagnosticsStoreTests {
    @Test
    func capsTrackedFiles() {
        let store = DiagnosticsStore(maxFileCount: 2, maxDiagnosticsPerFile: 5)
        store.setDiagnostics([diagnostic(path: "/tmp/a.swift")], for: "/tmp/a.swift")
        store.setDiagnostics([diagnostic(path: "/tmp/b.swift")], for: "/tmp/b.swift")
        store.setDiagnostics([diagnostic(path: "/tmp/c.swift")], for: "/tmp/c.swift")

        #expect(store.diagnostics(for: "/tmp/a.swift").isEmpty)
        #expect(store.diagnostics(for: "/tmp/b.swift").count == 1)
        #expect(store.diagnostics(for: "/tmp/c.swift").count == 1)
    }

    @Test
    func capsDiagnosticsPerFile() {
        let store = DiagnosticsStore(maxFileCount: 2, maxDiagnosticsPerFile: 2)
        store.setDiagnostics((0 ..< 5).map { diagnostic(path: "/tmp/a.swift", line: $0 + 1) }, for: "/tmp/a.swift")

        #expect(store.diagnostics(for: "/tmp/a.swift").count == 2)
    }

    private func diagnostic(path: String, line: Int = 1) -> EditorDiagnostic {
        EditorDiagnostic(
            id: "\(path):\(line)",
            filePath: path,
            relativePath: URL(fileURLWithPath: path).lastPathComponent,
            line: line,
            column: 1,
            severity: .warning,
            message: "issue",
            source: "test"
        )
    }
}
