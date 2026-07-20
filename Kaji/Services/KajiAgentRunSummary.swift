import Foundation

enum KajiAgentRunSummary {
    static func completionBody(from turns: [KajiAgentTurn]) -> String {
        for message in turns.reversed().flatMap({ $0.messages.reversed() }) {
            guard message.kind == .assistant || message.kind == .error else { continue }
            let text = (message.preview ?? message.detail).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            return clipped(text)
        }
        return "Kaji runtime finished"
    }

    static func clipped(_ text: String, limit: Int = 500) -> String {
        let cleaned = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > limit else { return cleaned }
        return String(cleaned.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    static func promptText(from event: KajiAgentSessionEvent) -> String? {
        guard event.type == "message_start", event.message?.role == "user" else { return nil }
        return clipped(KajiAgentTextExtractor.text(from: event.message?.content), limit: 240)
    }

    static func assistantText(from event: KajiAgentSessionEvent) -> String? {
        guard event.type == "message_end", event.message?.role == "assistant" else { return nil }
        let text = KajiAgentTextExtractor.assistantText(from: event.message?.content)
        return clipped(text, limit: 360)
    }

    static func toolText(from event: KajiAgentSessionEvent) -> String? {
        guard event.type == "tool_execution_start" else { return nil }
        let name = event.toolName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, !name.isEmpty else { return nil }
        return "Running \(name)"
    }
}
