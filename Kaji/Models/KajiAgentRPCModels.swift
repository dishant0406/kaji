import Foundation

struct KajiAgentRPCFrame: Codable {
    var id: String?
    var type: String
    var command: String?
    var success: Bool?
    var data: KajiAgentJSONValue?
    var error: String?
    var method: String?
    var title: String?
    var message: String?
    var placeholder: String?
    var notifyType: String?
    var pending: Bool?
    var allowEmpty: Bool?
    var isSecure: Bool?
    var options: [String]?
    var value: String?
    var prefill: String?
    var promptStyle: Bool?
    var timeout: Double?
    var timedOut: Bool?
    var confirmed: Bool?
    var cancelled: Bool?
    var url: String?
    var instructions: String?
    var targetId: String?
    var widgetKey: String?
    var widgetLines: [String]?
    var widgetPlacement: String?
    var statusKey: String?
    var statusText: String?
    var sessionID: String?
    var sessionId: String?
    var model: KajiAgentJSONValue?
    var thinkingLevel: String?
    var isStreaming: Bool?
    var messages: [KajiAgentRPCMessage]?
    var phases: [KajiAgentJSONValue]?
    var tools: [KajiAgentHostToolDefinition]?
    var schemes: [KajiAgentHostURISchemeDefinition]?
    var provider: String?
    var modelId: String?
    var level: String?
    var promptMessage: String?
    var images: [KajiAgentJSONValue]?
    var providerId: String?
    var providers: [KajiAgentLoginProvider]?
    var toolCallId: String?
    var toolName: String?
    var arguments: [String: KajiAgentJSONValue]?
    var result: KajiAgentToolResult?
    var partialResult: KajiAgentToolResult?
    var isError: Bool?
    var operation: String?
    var content: String?
    var contentType: String?
    var notes: [String]?
    var immutable: Bool?
    var event: KajiAgentSessionEvent?
    var text: String?
    var name: String?
    var query: String?
    var limit: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case command
        case success
        case data
        case error
        case method
        case title
        case message
        case placeholder
        case notifyType
        case pending
        case allowEmpty
        case isSecure
        case options
        case value
        case prefill
        case promptStyle
        case timeout
        case timedOut
        case confirmed
        case cancelled
        case url
        case instructions
        case targetId
        case widgetKey
        case widgetLines
        case widgetPlacement
        case statusKey
        case statusText
        case sessionID
        case sessionId
        case model
        case thinkingLevel
        case isStreaming
        case messages
        case phases
        case tools
        case schemes
        case provider
        case modelId
        case level
        case promptMessage
        case images
        case providerId
        case providers
        case toolCallId
        case toolName
        case arguments
        case result
        case partialResult
        case isError
        case operation
        case content
        case contentType
        case notes
        case immutable
        case event
        case assistantMessageEvent
        case args
        case text
        case name
        case query
        case limit
    }

    init(
        id: String? = nil,
        type: String,
        command: String? = nil,
        success: Bool? = nil,
        data: KajiAgentJSONValue? = nil,
        error: String? = nil,
        method: String? = nil,
        title: String? = nil,
        message: String? = nil,
        placeholder: String? = nil,
        notifyType: String? = nil,
        pending: Bool? = nil,
        allowEmpty: Bool? = nil,
        isSecure: Bool? = nil,
        options: [String]? = nil,
        value: String? = nil,
        prefill: String? = nil,
        promptStyle: Bool? = nil,
        timeout: Double? = nil,
        timedOut: Bool? = nil,
        confirmed: Bool? = nil,
        cancelled: Bool? = nil,
        url: String? = nil,
        instructions: String? = nil,
        targetId: String? = nil,
        widgetKey: String? = nil,
        widgetLines: [String]? = nil,
        widgetPlacement: String? = nil,
        statusKey: String? = nil,
        statusText: String? = nil,
        sessionID: String? = nil,
        sessionId: String? = nil,
        model: KajiAgentJSONValue? = nil,
        thinkingLevel: String? = nil,
        isStreaming: Bool? = nil,
        messages: [KajiAgentRPCMessage]? = nil,
        phases: [KajiAgentJSONValue]? = nil,
        tools: [KajiAgentHostToolDefinition]? = nil,
        schemes: [KajiAgentHostURISchemeDefinition]? = nil,
        provider: String? = nil,
        modelId: String? = nil,
        level: String? = nil,
        promptMessage: String? = nil,
        images: [KajiAgentJSONValue]? = nil,
        providerId: String? = nil,
        providers: [KajiAgentLoginProvider]? = nil,
        toolCallId: String? = nil,
        toolName: String? = nil,
        arguments: [String: KajiAgentJSONValue]? = nil,
        result: KajiAgentToolResult? = nil,
        partialResult: KajiAgentToolResult? = nil,
        isError: Bool? = nil,
        operation: String? = nil,
        content: String? = nil,
        contentType: String? = nil,
        notes: [String]? = nil,
        immutable: Bool? = nil,
        event: KajiAgentSessionEvent? = nil,
        text: String? = nil,
        name: String? = nil,
        query: String? = nil,
        limit: Int? = nil
    ) {
        self.id = id
        self.type = type
        self.command = command
        self.success = success
        self.data = data
        self.error = error
        self.method = method
        self.title = title
        self.message = message
        self.placeholder = placeholder
        self.notifyType = notifyType
        self.pending = pending
        self.allowEmpty = allowEmpty
        self.isSecure = isSecure
        self.options = options
        self.value = value
        self.prefill = prefill
        self.promptStyle = promptStyle
        self.timeout = timeout
        self.timedOut = timedOut
        self.confirmed = confirmed
        self.cancelled = cancelled
        self.url = url
        self.instructions = instructions
        self.targetId = targetId
        self.widgetKey = widgetKey
        self.widgetLines = widgetLines
        self.widgetPlacement = widgetPlacement
        self.statusKey = statusKey
        self.statusText = statusText
        self.sessionID = sessionID
        self.sessionId = sessionId
        self.model = model
        self.thinkingLevel = thinkingLevel
        self.isStreaming = isStreaming
        self.messages = messages
        self.phases = phases
        self.tools = tools
        self.schemes = schemes
        self.provider = provider
        self.modelId = modelId
        self.level = level
        self.promptMessage = promptMessage
        self.images = images
        self.providerId = providerId
        self.providers = providers
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.arguments = arguments
        self.result = result
        self.partialResult = partialResult
        self.isError = isError
        self.operation = operation
        self.content = content
        self.contentType = contentType
        self.notes = notes
        self.immutable = immutable
        self.event = event
        self.text = text
        self.name = name
        self.query = query
        self.limit = limit
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? container.decode(String.self, forKey: .type)) ?? "unknown"
        id = container.decodeLossy(String.self, forKey: .id)
        command = container.decodeLossy(String.self, forKey: .command)
        success = container.decodeLossy(Bool.self, forKey: .success)
        data = container.decodeLossy(KajiAgentJSONValue.self, forKey: .data)
        error = container.decodeLossy(String.self, forKey: .error)
        method = container.decodeLossy(String.self, forKey: .method)
        title = container.decodeLossy(String.self, forKey: .title)
        message = container.decodeLossy(String.self, forKey: .message)
        placeholder = container.decodeLossy(String.self, forKey: .placeholder)
        notifyType = container.decodeLossy(String.self, forKey: .notifyType)
        pending = container.decodeLossy(Bool.self, forKey: .pending)
        allowEmpty = container.decodeLossy(Bool.self, forKey: .allowEmpty)
        isSecure = container.decodeLossy(Bool.self, forKey: .isSecure)
        options = container.decodeLossy([String].self, forKey: .options)
        value = container.decodeLossy(String.self, forKey: .value)
        prefill = container.decodeLossy(String.self, forKey: .prefill)
        promptStyle = container.decodeLossy(Bool.self, forKey: .promptStyle)
        timeout = container.decodeLossy(Double.self, forKey: .timeout)
        timedOut = container.decodeLossy(Bool.self, forKey: .timedOut)
        confirmed = container.decodeLossy(Bool.self, forKey: .confirmed)
        cancelled = container.decodeLossy(Bool.self, forKey: .cancelled)
        url = container.decodeLossy(String.self, forKey: .url)
        instructions = container.decodeLossy(String.self, forKey: .instructions)
        targetId = container.decodeLossy(String.self, forKey: .targetId)
        widgetKey = container.decodeLossy(String.self, forKey: .widgetKey)
        widgetLines = container.decodeLossy([String].self, forKey: .widgetLines)
        widgetPlacement = container.decodeLossy(String.self, forKey: .widgetPlacement)
        statusKey = container.decodeLossy(String.self, forKey: .statusKey)
        statusText = container.decodeLossy(String.self, forKey: .statusText)
        sessionID = container.decodeLossy(String.self, forKey: .sessionID)
        sessionId = container.decodeLossy(String.self, forKey: .sessionId)
        model = container.decodeLossy(KajiAgentJSONValue.self, forKey: .model)
        thinkingLevel = container.decodeLossy(String.self, forKey: .thinkingLevel)
        isStreaming = container.decodeLossy(Bool.self, forKey: .isStreaming)
        messages = container.decodeLossy([KajiAgentRPCMessage].self, forKey: .messages)
        phases = container.decodeLossy([KajiAgentJSONValue].self, forKey: .phases)
        tools = container.decodeLossy([KajiAgentHostToolDefinition].self, forKey: .tools)
        schemes = container.decodeLossy([KajiAgentHostURISchemeDefinition].self, forKey: .schemes)
        provider = container.decodeLossy(String.self, forKey: .provider)
        modelId = container.decodeLossy(String.self, forKey: .modelId)
        level = container.decodeLossy(String.self, forKey: .level)
        promptMessage = container.decodeLossy(String.self, forKey: .promptMessage)
        images = container.decodeLossy([KajiAgentJSONValue].self, forKey: .images)
        providerId = container.decodeLossy(String.self, forKey: .providerId)
        providers = container.decodeLossy([KajiAgentLoginProvider].self, forKey: .providers)
        toolCallId = container.decodeLossy(String.self, forKey: .toolCallId)
        toolName = container.decodeLossy(String.self, forKey: .toolName)
        arguments = container.decodeLossy([String: KajiAgentJSONValue].self, forKey: .arguments)
        result = container.decodeLossy(KajiAgentToolResult.self, forKey: .result)
        partialResult = container.decodeLossy(KajiAgentToolResult.self, forKey: .partialResult)
        isError = container.decodeLossy(Bool.self, forKey: .isError)
        operation = container.decodeLossy(String.self, forKey: .operation)
        content = container.decodeLossy(String.self, forKey: .content)
        contentType = container.decodeLossy(String.self, forKey: .contentType)
        notes = container.decodeLossy([String].self, forKey: .notes)
        immutable = container.decodeLossy(Bool.self, forKey: .immutable)
        text = container.decodeLossy(String.self, forKey: .text)
        name = container.decodeLossy(String.self, forKey: .name)
        query = container.decodeLossy(String.self, forKey: .query)
        limit = container.decodeLossy(Int.self, forKey: .limit)
        event = container.decodeLossy(KajiAgentSessionEvent.self, forKey: .event)
        if event == nil, KajiAgentSessionEvent.sessionEventTypes.contains(type) {
            event = KajiAgentSessionEvent(container: container, type: type)
        }
    }

    func encode(to encoder: Encoder) throws {
        if ["generate_meeting_notes", "validate_meeting_notes_model"].contains(type), let fields = data?.objectValue {
            var container = encoder.container(keyedBy: KajiAgentDynamicCodingKey.self)
            try container.encodeIfPresent(id, forKey: .init("id"))
            try container.encode(type, forKey: .init("type"))
            for (key, value) in fields {
                try container.encode(value, forKey: .init(key))
            }
            return
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(command, forKey: .command)
        try container.encodeIfPresent(success, forKey: .success)
        try container.encodeIfPresent(data, forKey: .data)
        try container.encodeIfPresent(error, forKey: .error)
        try container.encodeIfPresent(method, forKey: .method)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(message, forKey: .message)
        try container.encodeIfPresent(placeholder, forKey: .placeholder)
        try container.encodeIfPresent(notifyType, forKey: .notifyType)
        try container.encodeIfPresent(pending, forKey: .pending)
        try container.encodeIfPresent(allowEmpty, forKey: .allowEmpty)
        try container.encodeIfPresent(isSecure, forKey: .isSecure)
        try container.encodeIfPresent(options, forKey: .options)
        try container.encodeIfPresent(value, forKey: .value)
        try container.encodeIfPresent(prefill, forKey: .prefill)
        try container.encodeIfPresent(promptStyle, forKey: .promptStyle)
        try container.encodeIfPresent(timeout, forKey: .timeout)
        try container.encodeIfPresent(timedOut, forKey: .timedOut)
        try container.encodeIfPresent(confirmed, forKey: .confirmed)
        try container.encodeIfPresent(cancelled, forKey: .cancelled)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encodeIfPresent(instructions, forKey: .instructions)
        try container.encodeIfPresent(targetId, forKey: .targetId)
        try container.encodeIfPresent(widgetKey, forKey: .widgetKey)
        try container.encodeIfPresent(widgetLines, forKey: .widgetLines)
        try container.encodeIfPresent(widgetPlacement, forKey: .widgetPlacement)
        try container.encodeIfPresent(statusKey, forKey: .statusKey)
        try container.encodeIfPresent(statusText, forKey: .statusText)
        try container.encodeIfPresent(sessionID, forKey: .sessionID)
        try container.encodeIfPresent(sessionId, forKey: .sessionId)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encodeIfPresent(thinkingLevel, forKey: .thinkingLevel)
        try container.encodeIfPresent(isStreaming, forKey: .isStreaming)
        try container.encodeIfPresent(messages, forKey: .messages)
        try container.encodeIfPresent(phases, forKey: .phases)
        try container.encodeIfPresent(tools, forKey: .tools)
        try container.encodeIfPresent(schemes, forKey: .schemes)
        try container.encodeIfPresent(provider, forKey: .provider)
        try container.encodeIfPresent(modelId, forKey: .modelId)
        try container.encodeIfPresent(level, forKey: .level)
        try container.encodeIfPresent(promptMessage, forKey: .promptMessage)
        try container.encodeIfPresent(images, forKey: .images)
        try container.encodeIfPresent(providerId, forKey: .providerId)
        try container.encodeIfPresent(providers, forKey: .providers)
        try container.encodeIfPresent(toolCallId, forKey: .toolCallId)
        try container.encodeIfPresent(toolName, forKey: .toolName)
        try container.encodeIfPresent(arguments, forKey: .arguments)
        try container.encodeIfPresent(result, forKey: .result)
        try container.encodeIfPresent(partialResult, forKey: .partialResult)
        try container.encodeIfPresent(isError, forKey: .isError)
        try container.encodeIfPresent(operation, forKey: .operation)
        try container.encodeIfPresent(content, forKey: .content)
        try container.encodeIfPresent(contentType, forKey: .contentType)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(immutable, forKey: .immutable)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(query, forKey: .query)
        try container.encodeIfPresent(limit, forKey: .limit)
        try container.encodeIfPresent(event, forKey: .event)
    }
}

private struct KajiAgentDynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

struct KajiAgentRPCMessage: Codable, Hashable {
    var role: String
    var content: KajiAgentJSONValue?
    var customType: String?
    var display: Bool?
    var details: KajiAgentJSONValue?
    var toolCallId: String?
    var toolName: String?
    var isError: Bool?
    var timestamp: Double?
    var stopReason: String?
    var errorMessage: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = (try? container.decode(String.self, forKey: .role)) ?? "unknown"
        content = container.decodeLossy(KajiAgentJSONValue.self, forKey: .content)
        customType = container.decodeLossy(String.self, forKey: .customType)
        display = container.decodeLossy(Bool.self, forKey: .display)
        details = container.decodeLossy(KajiAgentJSONValue.self, forKey: .details)
        toolCallId = container.decodeLossy(String.self, forKey: .toolCallId)
        toolName = container.decodeLossy(String.self, forKey: .toolName)
        isError = container.decodeLossy(Bool.self, forKey: .isError)
        timestamp = container.decodeLossy(Double.self, forKey: .timestamp)
        stopReason = container.decodeLossy(String.self, forKey: .stopReason)
        errorMessage = container.decodeLossy(String.self, forKey: .errorMessage)
    }
}

struct KajiAgentSessionEvent: Codable, Hashable {
    static let sessionEventTypes: Set<String> = [
        "agent_start", "agent_end", "turn_start", "turn_end", "message_start", "message_update", "message_end",
        "tool_execution_start", "tool_execution_update", "tool_execution_end", "auto_compaction_start",
        "auto_compaction_end", "auto_retry_start", "auto_retry_end", "retry_fallback_applied",
        "retry_fallback_succeeded", "ttsr_triggered", "todo_reminder", "todo_auto_clear", "irc_message", "notice",
        "thinking_level_changed", "goal_updated",
    ]

    var type: String
    var message: KajiAgentRPCMessage?
    var assistantMessageEvent: KajiAgentAssistantMessageEvent?
    var toolCallId: String?
    var toolName: String?
    var args: KajiAgentJSONValue?
    var partialResult: KajiAgentToolResult?
    var result: KajiAgentToolResult?
    var isError: Bool?

    init(
        type: String,
        message: KajiAgentRPCMessage? = nil,
        assistantMessageEvent: KajiAgentAssistantMessageEvent? = nil,
        toolCallId: String? = nil,
        toolName: String? = nil,
        args: KajiAgentJSONValue? = nil,
        partialResult: KajiAgentToolResult? = nil,
        result: KajiAgentToolResult? = nil,
        isError: Bool? = nil
    ) {
        self.type = type
        self.message = message
        self.assistantMessageEvent = assistantMessageEvent
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.args = args
        self.partialResult = partialResult
        self.result = result
        self.isError = isError
    }

    init(container: KeyedDecodingContainer<KajiAgentRPCFrame.CodingKeys>, type: String) {
        self.init(
            type: type,
            message: container.decodeLossy(KajiAgentRPCMessage.self, forKey: .message),
            assistantMessageEvent: container.decodeLossy(KajiAgentAssistantMessageEvent.self, forKey: .assistantMessageEvent),
            toolCallId: container.decodeLossy(String.self, forKey: .toolCallId),
            toolName: container.decodeLossy(String.self, forKey: .toolName),
            args: container.decodeLossy(KajiAgentJSONValue.self, forKey: .args),
            partialResult: container.decodeLossy(KajiAgentToolResult.self, forKey: .partialResult),
            result: container.decodeLossy(KajiAgentToolResult.self, forKey: .result),
            isError: container.decodeLossy(Bool.self, forKey: .isError)
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: KajiAgentRPCFrame.CodingKeys.self)
        self.init(container: container, type: (try? container.decode(String.self, forKey: .type)) ?? "unknown")
    }
}

struct KajiAgentAssistantMessageEvent: Codable, Hashable {
    var type: String
    var delta: String?
    var toolCall: KajiAgentToolCall?
    var contentIndex: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? container.decode(String.self, forKey: .type)) ?? "unknown"
        delta = container.decodeLossy(String.self, forKey: .delta)
        toolCall = container.decodeLossy(KajiAgentToolCall.self, forKey: .toolCall)
        contentIndex = container.decodeLossy(Int.self, forKey: .contentIndex)
    }
}

struct KajiAgentToolCall: Codable, Hashable {
    var id: String?
    var name: String?
    var arguments: KajiAgentJSONValue?
}

struct KajiAgentToolResult: Codable, Hashable {
    var content: [KajiAgentContentBlock]
    var details: KajiAgentJSONValue?
    var isError: Bool?

    init(content: [KajiAgentContentBlock] = [], details: KajiAgentJSONValue? = nil, isError: Bool? = nil) {
        self.content = content
        self.details = details
        self.isError = isError
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = container.decodeLossy([KajiAgentContentBlock].self, forKey: .content) ?? []
        details = container.decodeLossy(KajiAgentJSONValue.self, forKey: .details)
        isError = container.decodeLossy(Bool.self, forKey: .isError)
    }
}

struct KajiAgentContentBlock: Codable, Hashable {
    var type: String
    var text: String?
    var data: String?
    var mimeType: String?

    init(type: String, text: String? = nil, data: String? = nil, mimeType: String? = nil) {
        self.type = type
        self.text = text
        self.data = data
        self.mimeType = mimeType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? container.decode(String.self, forKey: .type)) ?? "text"
        text = container.decodeLossy(String.self, forKey: .text)
        data = container.decodeLossy(String.self, forKey: .data)
        mimeType = container.decodeLossy(String.self, forKey: .mimeType)
    }
}

struct KajiAgentHostToolDefinition: Codable, Hashable {
    let name: String
    let label: String?
    let description: String
    let parameters: KajiAgentJSONValue
    let hidden: Bool?
    var approval: String?
}

struct KajiAgentHostURISchemeDefinition: Codable, Hashable {
    let scheme: String
    let description: String?
    let writable: Bool?
    let immutable: Bool?
}

struct KajiAgentLoginProvider: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let available: Bool
    let authenticated: Bool
    var authProviderID: String?
    var modelProviderID: String?
    var availableModelCount: Int?
}

enum KajiAgentJSONValue: Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: KajiAgentJSONValue])
    case array([KajiAgentJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([KajiAgentJSONValue].self) {
            self = .array(value)
        } else {
            self = try .object(container.decode([String: KajiAgentJSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var stringValue: String? {
        switch self {
        case let .string(value): value
        case let .number(value): String(value)
        case let .bool(value): String(value)
        case .object,
             .array,
             .null: nil
        }
    }

    var numberValue: Double? {
        if case let .number(value) = self { return value }
        return nil
    }

    var boolValue: Bool? {
        if case let .bool(value) = self { return value }
        return nil
    }

    var objectValue: [String: KajiAgentJSONValue]? {
        if case let .object(value) = self { return value }
        return nil
    }

    var arrayValue: [KajiAgentJSONValue]? {
        if case let .array(value) = self { return value }
        return nil
    }
}

private extension KeyedDecodingContainer {
    func decodeLossy<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        try? decodeIfPresent(type, forKey: key)
    }
}
