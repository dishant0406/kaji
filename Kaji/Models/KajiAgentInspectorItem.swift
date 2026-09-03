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
        let descriptor = KajiAgentToolRenderer.descriptor(for: message)
        return KajiAgentInspectorItem(
            id: "tool.\(message.id.uuidString)",
            title: descriptor.title,
            subtitle: descriptor.subtitle,
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
}

extension KajiAgentMessage {
    var kajiAgentToolOutput: String? {
        if let fullOutput, !fullOutput.isEmpty {
            return fullOutput
        }
        if let preview, !preview.isEmpty {
            return preview
        }
        return nil
    }
}
