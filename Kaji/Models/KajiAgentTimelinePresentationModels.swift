import Foundation

struct KajiAgentPlanSummary: Identifiable, Hashable {
    let id: UUID
    let message: KajiAgentMessage
    let summary: String

    init(message: KajiAgentMessage) {
        id = message.id
        self.message = message
        summary = Self.summary(from: message.detail)
    }

    private static func summary(from text: String) -> String {
        let normalized = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "No plan details recorded."
        guard normalized.count > 180 else { return normalized }
        return String(normalized.prefix(177)) + "..."
    }
}

struct KajiAgentActivitySummary: Identifiable, Hashable {
    let id: UUID
    let group: KajiAgentToolGroup
    let actions: [KajiAgentActivityAction]

    init(group: KajiAgentToolGroup) {
        id = group.id
        self.group = group
        actions = group.tools.map(KajiAgentActivityAction.init(message:))
    }

    var title: String {
        if let active = actions.last(where: { !$0.isComplete }) { return active.title }
        if actions.count == 1, let action = actions.first { return action.title }
        return "Activity"
    }

    var summary: String {
        let failed = actions.filter(\.isError).count
        let running = actions.count(where: { !$0.isComplete })
        let output = actions.filter(\.hasOutput).count
        var parts = ["\(actions.count) action\(actions.count == 1 ? "" : "s")"]
        if running > 0 { parts.append("\(running) running") }
        if failed > 0 { parts.append("\(failed) failed") }
        if output > 0 { parts.append("\(output) with output") }
        return parts.joined(separator: " · ")
    }
}

struct KajiAgentActivityAction: Identifiable, Hashable {
    let id: UUID
    let message: KajiAgentMessage
    let title: String
    let detail: String
    let isComplete: Bool
    let isError: Bool
    let hasOutput: Bool

    init(message: KajiAgentMessage) {
        id = message.id
        self.message = message
        title = Self.title(for: message)
        detail = Self.detail(for: message)
        isComplete = message.isComplete
        isError = message.isError
        hasOutput = message.kajiAgentToolOutput != nil || message.taskDetails != nil
    }

    private static func title(for message: KajiAgentMessage) -> String {
        switch message.title {
        case "bash": "Ran command"
        case "read": "Read file"
        case "grep": "Searched code"
        case "glob": "Found files"
        case "webfetch": "Fetched page"
        case "google_search": "Researched web"
        case "apply_patch": "Edited files"
        default: message.title.nilIfEmpty ?? "Used tool"
        }
    }

    private static func detail(for message: KajiAgentMessage) -> String {
        if let arguments = message.toolArguments?.replacingOccurrences(of: "\n", with: " "), !arguments.isEmpty {
            return arguments.count > 140 ? String(arguments.prefix(137)) + "..." : arguments
        }
        if let preview = message.preview, !preview.isEmpty { return preview.count > 140 ? String(preview.prefix(137)) + "..." : preview }
        return message.isComplete ? "Complete" : "Running"
    }
}
