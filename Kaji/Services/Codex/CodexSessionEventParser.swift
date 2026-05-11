import Foundation

enum CodexSessionEventParser {
    struct FileContext: Equatable {
        var originator: String?
        var source: String?
        var cwd: String?
        var lastFinalMessage: String?
    }

    struct Completion: Equatable {
        let turnID: String
        let message: String
        let cwd: String?

        init(turnID: String, message: String, cwd: String? = nil) {
            self.turnID = turnID
            self.message = message
            self.cwd = cwd
        }
    }

    private static let interactiveOriginators: Set<String> = [
        "codex-tui",
        "codex_cli_rs",
        "Codex Desktop",
    ]

    static func consume(line: String, context: inout FileContext) -> Completion? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String
        else {
            return nil
        }

        if type == "session_meta" {
            let payload = object["payload"] as? [String: Any]
            context.originator = payload?["originator"] as? String
            context.source = payload?["source"] as? String
            context.cwd = payload?["cwd"] as? String
            return nil
        }

        if type == "event_msg",
           let payload = object["payload"] as? [String: Any],
           payload["type"] as? String == "agent_message",
           payload["phase"] as? String == "final_answer"
        {
            context.lastFinalMessage = normalizedOptionalMessage(payload["message"] as? String)
            return nil
        }

        if type == "response_item",
           let payload = object["payload"] as? [String: Any],
           payload["type"] as? String == "message",
           payload["role"] as? String == "assistant",
           payload["phase"] as? String == "final_answer"
        {
            context.lastFinalMessage = normalizedOptionalMessage(messageText(from: payload["content"]))
            return nil
        }

        guard type == "event_msg",
              let payload = object["payload"] as? [String: Any],
              payload["type"] as? String == "task_complete",
              let turnID = payload["turn_id"] as? String,
              isInteractive(context: context)
        else {
            return nil
        }

        let message = normalizedMessage(
            payload["last_agent_message"] as? String ?? context.lastFinalMessage
        )
        return Completion(turnID: turnID, message: message, cwd: context.cwd)
    }

    private static func isInteractive(context: FileContext) -> Bool {
        guard context.source != "exec",
              let originator = context.originator
        else {
            return false
        }

        return interactiveOriginators.contains(originator)
    }

    private static func normalizedMessage(_ message: String?) -> String {
        normalizedOptionalMessage(message) ?? "Turn completed"
    }

    private static func normalizedOptionalMessage(_ message: String?) -> String? {
        let cleaned = (message ?? "")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return nil }
        return String(cleaned.prefix(200))
    }

    private static func messageText(from content: Any?) -> String? {
        guard let items = content as? [[String: Any]] else { return nil }
        let parts = items.compactMap { item -> String? in
            guard item["type"] as? String == "output_text" else { return nil }
            return item["text"] as? String
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " ")
    }
}
