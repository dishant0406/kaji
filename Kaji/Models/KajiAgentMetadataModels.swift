struct KajiAgentSlashCommand: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    let source: String
    let inlineHint: String?
    let subcommands: [KajiAgentSlashSubcommand]

    init?(json: KajiAgentJSONValue) {
        guard let object = json.objectValue,
              let name = object["name"]?.stringValue
        else { return nil }
        self.id = "\(object["source"]?.stringValue ?? "runtime"):\(name)"
        self.name = name
        self.detail = object["description"]?.stringValue ?? object["source"]?.stringValue ?? "Runtime command"
        self.source = object["source"]?.stringValue ?? "runtime"
        self.inlineHint = object["inlineHint"]?.stringValue ?? object["argumentHint"]?.stringValue
        self.subcommands = object["subcommands"]?.arrayValue?.compactMap(KajiAgentSlashSubcommand.init(json:)) ?? []
    }
}

struct KajiAgentSlashSubcommand: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    let usage: String?

    init?(json: KajiAgentJSONValue) {
        guard let object = json.objectValue,
              let name = object["name"]?.stringValue
        else { return nil }
        self.id = name
        self.name = name
        self.detail = object["description"]?.stringValue ?? ""
        self.usage = object["usage"]?.stringValue
    }
}

struct KajiAgentSkillMetadata: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    let path: String

    init?(json: KajiAgentJSONValue) {
        guard let object = json.objectValue,
              let name = object["name"]?.stringValue,
              let path = object["path"]?.stringValue
        else { return nil }
        self.id = path
        self.name = name
        self.detail = object["description"]?.stringValue ?? path
        self.path = path
    }
}

struct KajiAgentHistoryMetadata: Identifiable, Hashable {
    let id: Int
    let prompt: String
    let createdAt: Double
    let cwd: String?

    init?(json: KajiAgentJSONValue) {
        guard let object = json.objectValue,
              let idValue = object["id"]?.numberValue,
              let prompt = object["prompt"]?.stringValue
        else { return nil }
        self.id = Int(idValue)
        self.prompt = prompt
        self.createdAt = object["createdAt"]?.numberValue ?? 0
        self.cwd = object["cwd"]?.stringValue
    }
}
