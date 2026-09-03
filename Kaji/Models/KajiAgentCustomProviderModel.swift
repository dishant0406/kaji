import Foundation

struct KajiAgentCustomProviderModel: Identifiable, Hashable {
    let localID: UUID
    var modelID: String
    var name: String
    var reasoning: Bool
    var supportsText: Bool
    var supportsImage: Bool
    var contextWindow: String
    var maxTokens: String

    var id: UUID { localID }

    init(
        localID: UUID = UUID(),
        modelID: String = "",
        name: String = "",
        reasoning: Bool = false,
        supportsText: Bool = true,
        supportsImage: Bool = false,
        contextWindow: String = "",
        maxTokens: String = ""
    ) {
        self.localID = localID
        self.modelID = modelID
        self.name = name
        self.reasoning = reasoning
        self.supportsText = supportsText
        self.supportsImage = supportsImage
        self.contextWindow = contextWindow
        self.maxTokens = maxTokens
    }

    init(json: KajiAgentJSONValue) {
        let object = json.objectValue ?? [:]
        let input = Set(object["input"]?.arrayValue?.compactMap(\.stringValue) ?? ["text"])
        localID = UUID()
        modelID = object["id"]?.stringValue ?? ""
        name = object["name"]?.stringValue ?? ""
        reasoning = object["reasoning"]?.boolValue ?? false
        supportsText = input.contains("text") || input.isEmpty
        supportsImage = input.contains("image")
        contextWindow = object["contextWindow"]?.numberAsInt.map(String.init) ?? ""
        maxTokens = object["maxTokens"]?.numberAsInt.map(String.init) ?? ""
    }

    var json: KajiAgentJSONValue {
        var object: [String: KajiAgentJSONValue] = [
            "id": .string(modelID.trimmed),
            "reasoning": .bool(reasoning),
            "input": .array(inputValues.map(KajiAgentJSONValue.string)),
        ]
        if !name.trimmed.isEmpty {
            object["name"] = .string(name.trimmed)
        }
        if let value = Int(contextWindow.trimmed) {
            object["contextWindow"] = .number(Double(value))
        }
        if let value = Int(maxTokens.trimmed) {
            object["maxTokens"] = .number(Double(value))
        }
        return .object(object)
    }

    var isValid: Bool {
        !modelID.trimmed.isEmpty
            && (supportsText || supportsImage)
            && positiveIntegerIfPresent(contextWindow)
            && positiveIntegerIfPresent(maxTokens)
    }

    private var inputValues: [String] {
        var values: [String] = []
        if supportsText {
            values.append("text")
        }
        if supportsImage {
            values.append("image")
        }
        return values.isEmpty ? ["text"] : values
    }

    private func positiveIntegerIfPresent(_ value: String) -> Bool {
        let trimmed = value.trimmed
        if trimmed.isEmpty {
            return true
        }
        return (Int(trimmed) ?? 0) > 0
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
