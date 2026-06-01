import Foundation

enum KajiAgentAttachmentFormatter {
    static func prompt(_ prompt: String, attachments: [AskAttachment]) -> String {
        guard !attachments.isEmpty else { return prompt }
        let title = prompt.isEmpty ? "Attached files:" : "\(prompt)\n\nAttached files:"
        let files = attachments.map { "- \($0.url.path)" }.joined(separator: "\n")
        return "\(title)\n\(files)"
    }
}
