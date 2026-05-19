import Foundation

enum EditorDiagnosticSeverity: Int, Comparable, Sendable {
    case error
    case warning
    case information
    case hint

    static func < (lhs: EditorDiagnosticSeverity, rhs: EditorDiagnosticSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct EditorDiagnostic: Identifiable, Equatable, Sendable {
    let id: String
    let filePath: String
    let relativePath: String
    let line: Int
    let column: Int
    let severity: EditorDiagnosticSeverity
    let message: String
    let source: String?
}

struct EditorDiagnosticFileGroup: Identifiable, Equatable, Sendable {
    let id: String
    let filePath: String
    let relativePath: String
    let diagnostics: [EditorDiagnostic]
}
