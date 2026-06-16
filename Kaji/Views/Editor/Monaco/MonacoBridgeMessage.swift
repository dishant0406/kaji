import Foundation

struct MonacoBridgeMessage: Decodable {
    let type: MonacoBridgeMessageType
    let editorID: String
    let payload: MonacoBridgePayload?
}

enum MonacoBridgeMessageType: String, Decodable {
    case ready
    case contentChanged
    case cursorChanged
    case selectionChanged
    case scrollChanged
    case saveRequested
    case focusChanged
    case inlineSelection
    case searchState
    case error
}

struct MonacoBridgePayload: Decodable {
    let version: Int?
    let edits: [MonacoTextEdit]?
    let line: Int?
    let column: Int?
    let selectionLength: Int?
    let text: String?
    let scrollTop: Double?
    let scrollHeight: Double?
    let viewportHeight: Double?
    let focused: Bool?
    let count: Int?
    let index: Int?
    let invalidRegex: Bool?
    let message: String?
}

struct MonacoTextEdit: Codable, Equatable {
    let range: MonacoRange
    let text: String
}

struct MonacoRange: Codable, Equatable {
    let startLineNumber: Int
    let startColumn: Int
    let endLineNumber: Int
    let endColumn: Int
}
