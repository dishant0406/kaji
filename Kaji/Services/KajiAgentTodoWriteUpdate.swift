enum KajiAgentTodoWriteUpdate: Hashable {
    case notTodo
    case failed(String)
    case missingPhases
    case phases([KajiAgentTodoPhase])

    static func live(result: KajiAgentToolResult?, toolName: String?, isError: Bool) -> KajiAgentTodoWriteUpdate {
        guard toolName == "todo_write" else { return .notTodo }
        if isError { return .failed(liveFailureDetail(from: result)) }
        return phases(from: result?.details)
    }

    static func restored(object: [String: KajiAgentJSONValue], toolName: String) -> KajiAgentTodoWriteUpdate {
        guard toolName == "todo_write" else { return .notTodo }
        if object["isError"]?.boolValue == true {
            let detail = KajiAgentTextExtractor.text(from: object["content"])
            return .failed(detail.isEmpty ? fallbackFailureDetail : detail)
        }
        return phases(from: object["details"])
    }

    private static func phases(from details: KajiAgentJSONValue?) -> KajiAgentTodoWriteUpdate {
        guard let phasesValue = details?.objectValue?["phases"],
              let phases = phasesValue.arrayValue?.compactMap(KajiAgentTodoPhase.init(json:)),
              !phases.isEmpty
        else { return .missingPhases }
        return .phases(phases)
    }

    private static func liveFailureDetail(from result: KajiAgentToolResult?) -> String {
        let detail = result?.content.compactMap(\.text).joined(separator: "\n") ?? ""
        return detail.isEmpty ? fallbackFailureDetail : detail
    }

    private static let fallbackFailureDetail = "Progress may be stale until todo_write succeeds."
}
