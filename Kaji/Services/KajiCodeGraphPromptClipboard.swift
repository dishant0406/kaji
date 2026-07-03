import AppKit

enum KajiCodeGraphPromptClipboard {
    static func copyCodeGraphDocument() {
        copy(KajiCodeGraphPromptTemplates.codeGraphDocument)
    }

    static func copyAgentsReference() {
        copy(KajiCodeGraphPromptTemplates.agentsReference)
    }

    static func copyClaudeReference() {
        copy(KajiCodeGraphPromptTemplates.claudeReference)
    }

    private static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
