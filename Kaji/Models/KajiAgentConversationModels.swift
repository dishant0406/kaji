import Foundation

struct KajiAgentMessage: Identifiable, Hashable {
    let id = UUID()
    var kind: KajiAgentMessageKind
    var title: String
    var detail: String
    var contentIndex: Int?
    var toolCallID: String?
    var toolArguments: String?
    var preview: String?
    var fullOutput: String?
    var taskDetails: KajiAgentTaskToolDetails?
    var truncatedLineCount = 0
    var isComplete = true
    var isError = false
    var isExpanded = false
}

struct KajiAgentTurn: Identifiable, Hashable {
    let id = UUID()
    var user: KajiAgentMessage?
    var blocks: [KajiAgentResponseBlock] = []
    var isActive = true
    var createdAt = Date()

    var messages: [KajiAgentMessage] {
        let response = blocks.flatMap(\.messages)
        if let user { return [user] + response }
        return response
    }

    var toolGroups: [KajiAgentToolGroup] {
        blocks.compactMap {
            if case let .toolGroup(group) = $0 { return group }
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
    let id = UUID()
    var tools: [KajiAgentMessage] = []
    var isExpanded = false

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
