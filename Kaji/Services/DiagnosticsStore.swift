import Foundation

@MainActor
@Observable
final class DiagnosticsStore {
    static let shared = DiagnosticsStore()

    private var diagnosticsByPath: [String: [EditorDiagnostic]] = [:]
    private var diagnosticFileOrder: [String] = []
    @ObservationIgnored private let maxFileCount: Int
    @ObservationIgnored private let maxDiagnosticsPerFile: Int

    init(maxFileCount: Int = 200, maxDiagnosticsPerFile: Int = 200) {
        self.maxFileCount = maxFileCount
        self.maxDiagnosticsPerFile = maxDiagnosticsPerFile
    }

    var allDiagnostics: [EditorDiagnostic] {
        diagnosticsByPath.values.flatMap(\.self).sorted(by: Self.sortDiagnostics)
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

    var errorCount: Int { allDiagnostics.count { $0.severity == .error } }
    var warningCount: Int { allDiagnostics.count { $0.severity == .warning } }

    func diagnostics(for filePath: String) -> [EditorDiagnostic] {
        diagnosticsByPath[filePath] ?? []
    }

    func setDiagnostics(_ diagnostics: [EditorDiagnostic], for filePath: String) {
        guard !diagnostics.isEmpty else {
            clearDiagnostics(for: filePath)
            return
        }
        diagnosticsByPath[filePath] = Array(diagnostics.sorted(by: Self.sortDiagnostics).prefix(maxDiagnosticsPerFile))
        touch(filePath)
        pruneIfNeeded()
    }

    func clearDiagnostics(for filePath: String) {
        diagnosticsByPath[filePath] = nil
        diagnosticFileOrder.removeAll { $0 == filePath }
    }

    func clearAll() {
        diagnosticsByPath = [:]
        diagnosticFileOrder = []
    }

    private func touch(_ filePath: String) {
        diagnosticFileOrder.removeAll { $0 == filePath }
        diagnosticFileOrder.append(filePath)
    }

    private func pruneIfNeeded() {
        while diagnosticFileOrder.count > maxFileCount {
            let removed = diagnosticFileOrder.removeFirst()
            diagnosticsByPath[removed] = nil
        }
    }

    private static func sortDiagnostics(_ lhs: EditorDiagnostic, _ rhs: EditorDiagnostic) -> Bool {
        if lhs.severity != rhs.severity { return lhs.severity < rhs.severity }
        if lhs.relativePath != rhs.relativePath { return lhs.relativePath < rhs.relativePath }
        if lhs.line != rhs.line { return lhs.line < rhs.line }
        return lhs.column < rhs.column
    }
}
