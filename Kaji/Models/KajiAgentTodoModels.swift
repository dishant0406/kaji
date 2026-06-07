struct KajiAgentTodoPhase: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let tasks: [KajiAgentTodoItem]

    init(name: String, tasks: [KajiAgentTodoItem]) {
        self.name = name
        self.tasks = tasks
    }

    init?(json: KajiAgentJSONValue) {
        guard let object = json.objectValue,
              let name = object["name"]?.stringValue
        else { return nil }
        self.name = name
        self.tasks = object["tasks"]?.arrayValue?.compactMap(KajiAgentTodoItem.init(json:)) ?? []
    }
}

struct KajiAgentTodoItem: Identifiable, Hashable {
    var id: String { content }
    let content: String
    let status: String
    let notes: [String]

    init(content: String, status: String, notes: [String] = []) {
        self.content = content
        self.status = status
        self.notes = notes
    }

    init?(json: KajiAgentJSONValue) {
        guard let object = json.objectValue,
              let content = object["content"]?.stringValue,
              let status = object["status"]?.stringValue
        else { return nil }
        self.content = content
        self.status = status
        self.notes = object["notes"]?.arrayValue?.compactMap(\.stringValue) ?? []
    }
}
