import Foundation

enum KajiCodeDiagnosticSeverity: Hashable {
    case info
    case warning
    case error
}

struct KajiCodeDiagnostic: Identifiable, Hashable {
    let id = UUID()
    let line: Int?
    let severity: KajiCodeDiagnosticSeverity
    let message: String
}
