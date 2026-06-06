extension KajiAgentJSONValue {
    var numberAsInt: Int? {
        if case let .number(value) = self { return Int(value) }
        return nil
    }

    var prettyDescription: String {
        switch self {
        case let .string(value): value
        case let .number(value): String(value)
        case let .bool(value): String(value)
        case let .array(values): values.map(\.prettyDescription).joined(separator: "\n")
        case let .object(values): values.map { "\($0.key): \($0.value.prettyDescription)" }.sorted().joined(separator: "\n")
        case .null: ""
        }
    }
}
