enum KajiAgentTextExtractor {
    static func text(from value: KajiAgentJSONValue?) -> String {
        blocks(from: value).map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    static func assistantText(from value: KajiAgentJSONValue?) -> String {
        blocks(from: value).filter { $0.kind == .text || $0.kind == .image }.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    static func thinkingText(from value: KajiAgentJSONValue?) -> String {
        blocks(from: value).filter { $0.kind == .thinking }.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    static func blocks(from value: KajiAgentJSONValue?) -> [KajiAgentContentPart] {
        switch value {
        case let .string(text):
            return [.init(kind: .text, text: text, index: 0)]
        case let .array(values):
            return values.enumerated().flatMap { offset, value in
                blocks(from: value).map { KajiAgentContentPart(kind: $0.kind, text: $0.text, index: $0.index ?? offset) }
            }
        case let .object(object):
            if object["type"]?.stringValue == "text" {
                return [.init(kind: .text, text: object["text"]?.stringValue ?? "", index: nil)]
            }
            if object["type"]?.stringValue == "thinking" {
                return [.init(kind: .thinking, text: object["thinking"]?.stringValue ?? "", index: nil)]
            }
            if object["type"]?.stringValue == "image" {
                let label = object["mimeType"]?.stringValue ?? object["mime_type"]?.stringValue ?? "image"
                return [.init(kind: .image, text: "[Image: \(label)]", index: nil)]
            }
            return []
        case .number, .bool, .null, .none:
            return []
        }
    }
}

struct KajiAgentContentPart: Hashable {
    enum Kind: Hashable {
        case text
        case thinking
        case image
    }

    let kind: Kind
    let text: String
    let index: Int?
}
