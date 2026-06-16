import Foundation

struct KajiAgentInspectorItem: Identifiable, Hashable {
    enum Kind: Hashable {
        case thinking(KajiAgentMessage)
        case tool(KajiAgentMessage)
        case toolGroup(KajiAgentToolGroup)
    }

    let id: String
    let title: String
    let subtitle: String
    let kind: Kind

    static func thinking(_ message: KajiAgentMessage) -> KajiAgentInspectorItem {
        KajiAgentInspectorItem(
            id: "thinking.\(message.id.uuidString)",
            title: message.isComplete ? "Plan" : "Planning",
            subtitle: message.isComplete ? "Reasoning trace" : "Live reasoning trace",
            kind: .thinking(message)
        )
    }

    static func tool(_ message: KajiAgentMessage) -> KajiAgentInspectorItem {
        KajiAgentInspectorItem(
            id: "tool.\(message.id.uuidString)",
            title: message.title,
            subtitle: toolSubtitle(message),
            kind: .tool(message)
        )
    }

    static func toolGroup(_ group: KajiAgentToolGroup) -> KajiAgentInspectorItem {
        KajiAgentInspectorItem(
            id: "toolGroup.\(group.id.uuidString)",
            title: group.title,
            subtitle: "\(group.tools.count) action\(group.tools.count == 1 ? "" : "s")",
            kind: .toolGroup(group)
        )
    }

    private static func toolSubtitle(_ message: KajiAgentMessage) -> String {
        if message.isError { return "Failed" }
        if !message.isComplete { return "Running" }
        if message.fullOutput?.isEmpty == false || message.preview?.isEmpty == false { return "Output available" }
        if message.taskDetails != nil { return "Task details" }
        return "No output"
    }
}

extension KajiAgentMessage {
    var kajiAgentToolOutput: String? {
        if let fullOutput, !fullOutput.isEmpty { return fullOutput }
        if let preview, !preview.isEmpty { return preview }
        return nil
    }
}
