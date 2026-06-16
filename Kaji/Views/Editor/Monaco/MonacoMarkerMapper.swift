import Foundation

enum MonacoMarkerMapper {
    static func markers(for diagnostics: [EditorDiagnostic]) -> [MonacoJSONValue] {
        diagnostics.map { diagnostic in
            let column = max(1, diagnostic.column)
            return .object([
                "startLineNumber": .int(max(1, diagnostic.line)),
                "startColumn": .int(column),
                "endLineNumber": .int(max(1, diagnostic.line)),
                "endColumn": .int(column + 1),
                "severity": .string(severity(diagnostic.severity)),
                "message": .string(diagnostic.message),
                "source": .string(diagnostic.source ?? "Kaji"),
            ])
        }
    }

    private static func severity(_ severity: EditorDiagnosticSeverity) -> String {
        switch severity {
        case .error: "error"
        case .warning: "warning"
        case .information: "information"
        case .hint: "hint"
        }
    }
}
