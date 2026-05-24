import Foundation

struct LSPPosition: Codable, Equatable {
    let line: Int
    let character: Int
}

struct LSPRange: Codable, Equatable {
    let start: LSPPosition
    let end: LSPPosition
}

struct LSPDiagnostic: Codable, Equatable {
    let range: LSPRange
    let severity: Int?
    let source: String?
    let message: String
}

struct LSPPublishDiagnosticsParams: Codable, Equatable {
    let uri: String
    let diagnostics: [LSPDiagnostic]
}

struct LSPMessage: Codable, Equatable {
    let jsonrpc: String
    let id: Int?
    let method: String?
    let params: JSONValue?
    let result: JSONValue?
    let error: JSONValue?
}

enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = try .object(container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
