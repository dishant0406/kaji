struct KajiAgentRuntimeStateSnapshot: Equatable {
    let sessionID: String?
    let thinkingLevel: String?
    let queuedMessageCount: Int?
    let todoPhases: [KajiAgentTodoPhase]?
    let modelLabel: String?
    let isRunning: Bool?

    init?(json: KajiAgentJSONValue?) {
        guard let data = json?.objectValue else { return nil }
        sessionID = data["sessionId"]?.stringValue ?? data["sessionID"]?.stringValue
        thinkingLevel = data["thinkingLevel"]?.stringValue
        queuedMessageCount = data["queuedMessageCount"]?.intValue
        todoPhases = data["todoPhases"]?.arrayValue?.compactMap(KajiAgentTodoPhase.init(json:))
        modelLabel = Self.modelLabel(from: data["model"])
        isRunning = data["isStreaming"]?.boolValue
    }

    static func modelLabel(from value: KajiAgentJSONValue?) -> String? {
        guard let model = value?.objectValue else { return nil }
        let provider = model["provider"]?.stringValue ?? "provider"
        let id = model["id"]?.stringValue ?? "model"
        return "\(provider) / \(id)"
    }
}

private extension KajiAgentJSONValue {
    var intValue: Int? {
        if case let .number(value) = self { return Int(value) }
        return nil
    }
}
