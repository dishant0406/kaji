import Foundation

enum DroidCodeDiagnosticSeverity: Hashable {
    case info
    case warning
    case error
}

struct DroidCodeDiagnostic: Identifiable, Hashable {
    let id = UUID()
    let line: Int?
    let severity: DroidCodeDiagnosticSeverity
    let message: String
}

enum DroidCodeLanguage: Hashable {
    case shell
}
