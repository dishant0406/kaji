import Foundation

struct KajiAgentMessage: Identifiable, Hashable {
    let id: UUID
    var kind: KajiAgentMessageKind
    var title: String
    var detail: String
    var contentIndex: Int?
    var toolCallID: String?
    var toolArguments: String?
    var preview: String?
    var fullOutput: String?
    var taskDetails: KajiAgentTaskToolDetails?
    var truncatedLineCount: Int
    var isComplete: Bool
    var isError: Bool
    var isExpanded: Bool

    init(
        id: UUID = UUID(),
        kind: KajiAgentMessageKind,
        title: String,
        detail: String,
        contentIndex: Int? = nil,
        toolCallID: String? = nil,
        toolArguments: String? = nil,
        preview: String? = nil,
        fullOutput: String? = nil,
        taskDetails: KajiAgentTaskToolDetails? = nil,
        truncatedLineCount: Int = 0,
        isComplete: Bool = true,
        isError: Bool = false,
        isExpanded: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.contentIndex = contentIndex
        self.toolCallID = toolCallID
        self.toolArguments = toolArguments
        self.preview = preview
        self.fullOutput = fullOutput
        self.taskDetails = taskDetails
        self.truncatedLineCount = truncatedLineCount
        self.isComplete = isComplete
        self.isError = isError
        self.isExpanded = isExpanded
    }
}

struct KajiAgentTurn: Identifiable, Hashable {
    let id: UUID
    var user: KajiAgentMessage?
    var blocks: [KajiAgentResponseBlock]
    var isActive: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        user: KajiAgentMessage? = nil,
        blocks: [KajiAgentResponseBlock] = [],
        isActive: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.user = user
        self.blocks = blocks
        self.isActive = isActive
        self.createdAt = createdAt
    }

    var messages: [KajiAgentMessage] {
        let response = blocks.flatMap(\.messages)
        if let user {
            return [user] + response
        }
        return response
    }

    var toolGroups: [KajiAgentToolGroup] {
        blocks.compactMap {
            if case let .toolGroup(group) = $0 {
                return group
            }
            return nil
        }
    }
}

enum KajiAgentResponseBlock: Identifiable, Hashable {
    case message(KajiAgentMessage)
    case toolGroup(KajiAgentToolGroup)

    var id: UUID {
        switch self {
        case let .message(message): message.id
        case let .toolGroup(group): group.id
        }
    }

    var messages: [KajiAgentMessage] {
        switch self {
        case let .message(message): [message]
        case let .toolGroup(group): group.tools
        }
    }

    var debugName: String {
        switch self {
        case let .message(message):
            "message:\(message.kind)"
        case let .toolGroup(group):
            "toolGroup:\(group.tools.count)"
        }
    }
}

struct KajiAgentToolGroup: Identifiable, Hashable {
    let id: UUID
    var tools: [KajiAgentMessage]
    var isExpanded: Bool

    init(id: UUID = UUID(), tools: [KajiAgentMessage] = [], isExpanded: Bool = false) {
        self.id = id
        self.tools = tools
        self.isExpanded = isExpanded
    }

    var title: String {
        if let running = tools.last(where: { !$0.isComplete }) {
            return running.title
        }
        guard tools.count != 1 else { return tools[0].title }
        return "Tools called (\(tools.count))"
    }

    var hasError: Bool { tools.contains { $0.isError } }
    var isComplete: Bool { tools.allSatisfy(\.isComplete) }
}

enum KajiAgentMessageKind: Hashable {
    case user
    case assistant
    case thinking
    case tool
    case event
    case error
}

struct KajiAgentQuestion: Hashable {
    let id: String
    let title: String
    var method: String = "input"
    var placeholder: String?
    var prefill: String?
    var promptStyle = false
    var isSecure = false
    var allowEmpty = false
    var timeout: Double?
    let options: [String]
}

struct KajiAgentWidget: Identifiable, Hashable {
    var id: String { key }
    let key: String
    let placement: String
    let lines: [String]
}
