import Foundation

@MainActor
@Observable
final class DiagnosticsStore {
    static let shared = DiagnosticsStore()

    private var diagnosticsByPath: [String: [EditorDiagnostic]] = [:]

    var allDiagnostics: [EditorDiagnostic] {
        diagnosticsByPath.values.flatMap { $0 }.sorted(by: Self.sortDiagnostics)
    }

    var groups: [EditorDiagnosticFileGroup] {
        diagnosticsByPath.keys.sorted().compactMap { path in
            guard let diagnostics = diagnosticsByPath[path], !diagnostics.isEmpty else { return nil }
            return EditorDiagnosticFileGroup(
                id: path,
                filePath: path,
                relativePath: diagnostics.first?.relativePath ?? URL(fileURLWithPath: path).lastPathComponent,
                diagnostics: diagnostics.sorted(by: Self.sortDiagnostics)
            )
        }
    }

    var errorCount: Int { allDiagnostics.filter { $0.severity == .error }.count }
    var warningCount: Int { allDiagnostics.filter { $0.severity == .warning }.count }

    func diagnostics(for filePath: String) -> [EditorDiagnostic] {
        diagnosticsByPath[filePath] ?? []
    }

    func setDiagnostics(_ diagnostics: [EditorDiagnostic], for filePath: String) {
        diagnosticsByPath[filePath] = diagnostics.sorted(by: Self.sortDiagnostics)
    }

    func clearDiagnostics(for filePath: String) {
        diagnosticsByPath[filePath] = nil
    }

    func clearAll() {
        diagnosticsByPath = [:]
    }

    private static func sortDiagnostics(_ lhs: EditorDiagnostic, _ rhs: EditorDiagnostic) -> Bool {
        if lhs.severity != rhs.severity { return lhs.severity < rhs.severity }
        if lhs.relativePath != rhs.relativePath { return lhs.relativePath < rhs.relativePath }
        if lhs.line != rhs.line { return lhs.line < rhs.line }
        return lhs.column < rhs.column
    }
}
