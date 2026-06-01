struct KajiAgentModelRoleAssignment: Identifiable, Hashable {
    let id: String
    let role: String
    let name: String
    let tag: String?
    let selector: String?

    init?(json: KajiAgentJSONValue) {
        guard let object = json.objectValue,
              let role = object["role"]?.stringValue,
              let name = object["name"]?.stringValue
        else { return nil }
        self.id = role
        self.role = role
        self.name = name
        self.tag = object["tag"]?.stringValue
        self.selector = object["selector"]?.stringValue
    }
}

struct KajiAgentModelConfig: Hashable {
    let roles: [KajiAgentModelRoleAssignment]
    let cycleOrder: [String]
    let models: [KajiAgentModelOption]

    init(json: KajiAgentJSONValue?) {
        let object = json?.objectValue ?? [:]
        roles = object["roles"]?.arrayValue?.compactMap(KajiAgentModelRoleAssignment.init(json:)) ?? []
        cycleOrder = object["cycleOrder"]?.arrayValue?.compactMap(\.stringValue) ?? []
        models = KajiAgentModelOption.options(from: json)
    }
}
