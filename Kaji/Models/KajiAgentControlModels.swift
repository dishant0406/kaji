struct KajiAgentToolOption: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    var isActive: Bool

    init?(json: KajiAgentJSONValue) {
        guard let object = json.objectValue,
              let name = object["name"]?.stringValue
        else { return nil }
        self.id = name
        self.name = name
        self.detail = object["description"]?.stringValue ?? ""
        self.isActive = if case let .bool(value)? = object["active"] {
            value
        } else {
            false
        }
    }
}

struct KajiAgentSessionOption: Identifiable, Hashable {
    let id: String
    let path: String
    let title: String
    let detail: String

    init?(json: KajiAgentJSONValue) {
        guard let object = json.objectValue,
              let path = object["path"]?.stringValue,
              let id = object["id"]?.stringValue
        else { return nil }
        self.id = path
        self.path = path
        let title = object["title"]?.stringValue ?? object["firstMessage"]?.stringValue ?? id
        self.title = title.isEmpty ? id : title
        let cwd = object["cwd"]?.stringValue ?? ""
        let count = object["messageCount"]?.numberValue.map { Int($0) } ?? 0
        self.detail = cwd.isEmpty ? "\(count) messages" : "\(cwd) · \(count) messages"
    }
}

enum KajiAgentPanel: Hashable {
    case models
    case login
    case tools
    case sessions
}
