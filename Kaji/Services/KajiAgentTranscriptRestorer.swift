import Foundation

struct KajiAgentTranscriptRestoration {
    let turns: [KajiAgentTurn]
    let activeTurnID: KajiAgentTurn.ID?
    let todoPhases: [KajiAgentTodoPhase]?
}

struct KajiAgentTranscriptRestorer {
    var turns: [KajiAgentTurn] = []
    var activeTurnID: KajiAgentTurn.ID?
    var todoPhases: [KajiAgentTodoPhase]?
    private var messageOrdinal = 0
    private var turnOrdinal = 0

    static func restore(from value: KajiAgentJSONValue?) -> KajiAgentTranscriptRestoration? {
        guard let values = value?.objectValue?["messages"]?.arrayValue else { return nil }
        var restorer = KajiAgentTranscriptRestorer()
        restorer.restore(values)
        return KajiAgentTranscriptRestoration(
            turns: restorer.turns,
            activeTurnID: restorer.activeTurnID,
            todoPhases: restorer.todoPhases
        )
    }

    private func messageID(_ parts: String...) -> UUID {
        KajiAgentTranscriptIdentity.uuid(([String(messageOrdinal)] + parts).joined(separator: "\u{1f}"))
    }

    private mutating func restore(_ values: [KajiAgentJSONValue]) {
        for value in values {
            guard let object = value.objectValue,
                  let role = object["role"]?.stringValue
            else { continue }
            restore(object, role: role)
            messageOrdinal += 1
        }
    }

    private mutating func restore(_ object: [String: KajiAgentJSONValue], role: String) {
        let text = KajiAgentTextExtractor.text(from: object["content"])
        switch role {
        case "user":
            startTurn(user: KajiAgentMessage(id: messageID("user", text), kind: .user, title: "You", detail: text))
        case "assistant":
            restoreAssistantContent(object["content"])
            if let error = object["errorMessage"]?.stringValue, !error.isEmpty {
                appendMessage(KajiAgentMessage(id: messageID("error", error), kind: .error, title: "Provider error", detail: error))
            }
        case "toolResult":
            restoreToolResult(object)
        default:
            guard object["display"]?.boolValue != false else { return }
            appendMessage(KajiAgentMessage(
                id: messageID("event", role, text),
                kind: .event,
                title: object["customType"]?.stringValue ?? role,
                detail: text
            ))
        }
    }

    private mutating func restoreAssistantContent(_ content: KajiAgentJSONValue?) {
        guard let values = content?.arrayValue else {
            let text = KajiAgentTextExtractor.assistantText(from: content)
            if !text.isEmpty {
                appendMessage(KajiAgentMessage(
                    id: messageID("assistant", text),
                    kind: .assistant,
                    title: "Kaji",
                    detail: text
                ))
            }
            return
        }
        for (partIndex, value) in values.enumerated() {
            guard let object = value.objectValue, let type = object["type"]?.stringValue else { continue }
            switch type {
            case "thinking":
                appendTextMessage(kind: .thinking, title: "Thinking", text: object["thinking"]?.stringValue ?? "", key: "part.\(partIndex)")
            case "text":
                appendTextMessage(kind: .assistant, title: "Kaji", text: object["text"]?.stringValue ?? "", key: "part.\(partIndex)")
            case "image":
                let label = object["mimeType"]?.stringValue ?? object["mime_type"]?.stringValue ?? "image"
                appendMessage(KajiAgentMessage(
                    id: messageID("image", "part.\(partIndex)", label),
                    kind: .assistant,
                    title: "Kaji",
                    detail: "[Image: \(label)]"
                ))
            case "toolCall":
                restoreToolCall(object)
            default:
                break
            }
        }
    }

    private mutating func restoreToolCall(_ object: [String: KajiAgentJSONValue]) {
        let id = object["id"]?.stringValue ?? KajiAgentTranscriptIdentity.uuid("restored-tool", String(messageOrdinal)).uuidString
        ensureActiveTurn()
        appendTool(KajiAgentMessage(
            id: toolMessageID(id),
            kind: .tool,
            title: object["name"]?.stringValue ?? "Tool",
            detail: "Pending result",
            toolCallID: id,
            toolArguments: object["arguments"]?.prettyDescription,
            isComplete: false
        ))
    }

    private func toolMessageID(_ id: String) -> UUID {
        KajiAgentTranscriptIdentity.uuid("tool", activeTurnID?.uuidString ?? "no-turn", String(messageOrdinal), id)
    }

    private mutating func restoreToolResult(_ object: [String: KajiAgentJSONValue]) {
        let id = object["toolCallId"]?.stringValue ?? KajiAgentTranscriptIdentity.uuid("restored-tool-result", String(messageOrdinal))
            .uuidString
        let name = object["toolName"]?.stringValue ?? "Tool"
        if toolLocation(id: id) == nil {
            ensureActiveTurn()
            appendTool(KajiAgentMessage(
                id: toolMessageID(id),
                kind: .tool,
                title: name,
                detail: "",
                toolCallID: id,
                isComplete: false
            ))
        }
        guard let location = toolLocation(id: id) else { return }
        updateToolOutput(at: location, output: KajiAgentTextExtractor.text(from: object["content"]), complete: true)
        updateTool(at: location) { tool in
            tool.isComplete = true
            tool.isError = object["isError"]?.boolValue == true
        }
        restoreTodoPhases(from: object, toolName: name)
    }

    private mutating func restoreTodoPhases(from object: [String: KajiAgentJSONValue], toolName: String) {
        switch KajiAgentTodoWriteUpdate.restored(object: object, toolName: toolName) {
        case .notTodo,
             .missingPhases:
            return
        case let .failed(detail):
            appendMessage(KajiAgentMessage(id: messageID("todo-error", detail), kind: .error, title: "Todo update failed", detail: detail))
        case let .phases(phases):
            todoPhases = phases
        }
    }

    private mutating func appendTextMessage(kind: KajiAgentMessageKind, title: String, text: String, key: String) {
        if !text.isEmpty {
            appendMessage(KajiAgentMessage(id: messageID("\(kind)", key, text), kind: kind, title: title, detail: text))
        }
    }

    private mutating func startTurn(user: KajiAgentMessage) {
        let turn = KajiAgentTurn(id: KajiAgentTranscriptIdentity.uuid("restored-turn", String(turnOrdinal), user.id.uuidString), user: user)
        turnOrdinal += 1
        turns.append(turn)
        activeTurnID = turn.id
    }

    private mutating func appendMessage(_ message: KajiAgentMessage) {
        ensureActiveTurn()
        guard let index = activeTurnIndex() else { return }
        turns[index].blocks.append(.message(message))
    }

    private mutating func appendTool(_ tool: KajiAgentMessage) {
        ensureActiveTurn()
        guard let turnIndex = activeTurnIndex() else { return }
        if let blockIndex = turns[turnIndex].blocks.indices.last,
           case var .toolGroup(group) = turns[turnIndex].blocks[blockIndex]
        {
            group.tools.append(tool)
            turns[turnIndex].blocks[blockIndex] = .toolGroup(group)
            return
        }
        turns[turnIndex].blocks.append(.toolGroup(KajiAgentToolGroup(
            id: KajiAgentTranscriptIdentity.uuid("toolGroup", turns[turnIndex].id.uuidString, tool.id.uuidString),
            tools: [tool]
        )))
    }

    private mutating func ensureActiveTurn() {
        if activeTurnIndex() != nil {
            return
        }
        let turn = KajiAgentTurn(id: KajiAgentTranscriptIdentity.uuid("restored-turn", String(turnOrdinal)))
        turnOrdinal += 1
        turns.append(turn)
        activeTurnID = turn.id
    }

    private func activeTurnIndex() -> Int? {
        guard let activeTurnID else { return nil }
        return turns.firstIndex { $0.id == activeTurnID }
    }
}
