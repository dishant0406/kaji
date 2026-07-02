import Foundation
import TermyKit

struct TermyConfigDiagnostic: Equatable, Identifiable {
    let lineNumber: Int
    let kind: Kind
    let message: String

    var id: String { "\(lineNumber)-\(kind.rawValue)-\(message)" }

    enum Kind: UInt32, Equatable {
        case unknownSection = 1
        case unknownRootKey = 2
        case unknownColorKey = 3
        case invalidSyntax = 4
        case invalidValue = 5
        case duplicateRootKey = 6
        case unknown = 0

        var label: String {
            switch self {
            case .unknownSection: "Unknown section"
            case .unknownRootKey: "Unknown setting"
            case .unknownColorKey: "Unknown color"
            case .invalidSyntax: "Invalid syntax"
            case .invalidValue: "Invalid value"
            case .duplicateRootKey: "Duplicate setting"
            case .unknown: "Config issue"
            }
        }
    }
}

enum TermyConfigDiagnostics {
    static func load(contents: String) -> [TermyConfigDiagnostic] {
        var config: OpaquePointer?
        let status = Array(contents.utf8).withUnsafeBufferPointer { buffer in
            termy_config_from_contents(buffer.baseAddress, buffer.count, &config)
        }
        guard status == TERMY_FFI_OK, let config else { return [] }
        defer { termy_config_free(config) }
        return load(from: config)
    }

    static func load(path: String) -> [TermyConfigDiagnostic] {
        var config: OpaquePointer?
        let status = Array(path.utf8).withUnsafeBufferPointer { buffer in
            termy_config_load_path(buffer.baseAddress, buffer.count, &config)
        }
        guard status == TERMY_FFI_OK, let config else { return [] }
        defer { termy_config_free(config) }
        return load(from: config)
    }

    private static func load(from config: OpaquePointer) -> [TermyConfigDiagnostic] {
        var batch = TermyFfiConfigDiagnosticBatch()
        guard termy_config_diagnostics(config, &batch) == TERMY_FFI_OK else { return [] }
        defer { termy_config_diagnostics_free(&batch) }
        guard let pointer = batch.diagnostics_ptr, batch.diagnostics_len > 0 else { return [] }
        return UnsafeBufferPointer(start: pointer, count: Int(batch.diagnostics_len)).map { item in
            TermyConfigDiagnostic(
                lineNumber: Int(item.line_number),
                kind: TermyConfigDiagnostic.Kind(rawValue: item.kind) ?? .unknown,
                message: TermyBytes.string(item.message) ?? "Invalid Termy config value"
            )
        }
    }
}
