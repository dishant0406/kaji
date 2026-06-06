struct KajiAgentModelOption: Identifiable, Hashable {
    let id: String
    let provider: String
    let modelID: String
    let title: String

    static func options(from value: KajiAgentJSONValue?) -> [KajiAgentModelOption] {
        guard case let .object(data)? = value,
              case let .array(models)? = data["models"]
        else { return [] }
        return models.compactMap { value in
            guard let object = value.objectValue,
                  let provider = object["provider"]?.stringValue,
                  let id = object["id"]?.stringValue
            else { return nil }
            return KajiAgentModelOption(id: "\(provider)/\(id)", provider: provider, modelID: id, title: "\(provider) / \(id)")
        }
    }
}
