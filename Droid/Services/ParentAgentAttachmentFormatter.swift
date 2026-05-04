import Foundation
import UniformTypeIdentifiers

enum ParentAgentAttachmentFormatter {
    static func prompt(_ prompt: String, attachments: [AskAttachment]) -> String {
        guard !attachments.isEmpty else { return prompt }
        let title = prompt.isEmpty ? "Attached files:" : "\(prompt)\n\nAttached files:"
        let files = attachments.map { "- \($0.url.path)" }.joined(separator: "\n")
        return "\(title)\n\(files)"
    }

    static func contexts(_ attachments: [AskAttachment]) -> [ParentAgentAttachmentContext] {
        attachments.map { attachment in
            ParentAgentAttachmentContext(
                name: attachment.name,
                path: attachment.url.path,
                kind: attachment.kind.rawValue,
                mimeType: mimeType(for: attachment.url),
                data: imageData(for: attachment)
            )
        }
    }

    private static func mimeType(for url: URL) -> String {
        UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }

    private static func imageData(for attachment: AskAttachment) -> String? {
        guard attachment.kind == .image else { return nil }
        return try? Data(contentsOf: attachment.url).base64EncodedString()
    }
}
