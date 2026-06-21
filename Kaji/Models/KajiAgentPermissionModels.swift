import Foundation

struct KajiAgentApprovalRequest: Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String
    let toolName: String
    let receivedAt: Date
    let options: [KajiAgentApprovalOption]

    init(
        id: String,
        title: String,
        summary: String,
        toolName: String? = nil,
        receivedAt: Date = Date(),
        options: [KajiAgentApprovalOption] = KajiAgentApprovalOption.defaultOptions
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.toolName = toolName ?? KajiAgentApprovalRequest.inferToolName(from: summary)
        self.receivedAt = receivedAt
        self.options = options
    }

    static func fromConfirm(id: String, title: String?, message: String?) -> KajiAgentApprovalRequest? {
        let rawTitle = title ?? ""
        let rawMessage = message ?? ""
        let combined = "\(rawTitle) \(rawMessage)".lowercased()
        guard combined.contains("permission") || combined.contains("allow ") || combined.contains("approve") else { return nil }
        let titleText = title ?? "Permission required"
        let summaryText = message ?? titleText
        return KajiAgentApprovalRequest(id: id, title: titleText, summary: summaryText)
    }

    private static func inferToolName(from value: String) -> String {
        let cleaned = value
            .replacingOccurrences(of: "Allow", with: "")
            .replacingOccurrences(of: "?", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = cleaned.split(separator: ":").first else { return "Tool" }
        let name = first.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Tool" : name
    }
}

struct KajiAgentApprovalOption: Identifiable, Hashable {
    let id: String
    let title: String
    let isAllow: Bool
    let isDestructive: Bool

    static let defaultOptions = [
        KajiAgentApprovalOption(id: "allow_once", title: "Allow", isAllow: true, isDestructive: false),
        KajiAgentApprovalOption(id: "deny_once", title: "Deny", isAllow: false, isDestructive: true),
    ]
}
