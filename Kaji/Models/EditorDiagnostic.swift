import Foundation

enum EditorDiagnosticSeverity: Int, Comparable {
    case error
    case warning
    case information
    case hint

    static func < (lhs: EditorDiagnosticSeverity, rhs: EditorDiagnosticSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct EditorDiagnostic: Identifiable, Equatable {
    let id: String
    let filePath: String
    let relativePath: String
    let line: Int
    let column: Int
    let severity: EditorDiagnosticSeverity
    let message: String
    let source: String?
}

struct EditorDiagnosticFileGroup: Identifiable, Equatable {
    let id: String
    let filePath: String
    let relativePath: String
    let diagnostics: [EditorDiagnostic]
}
