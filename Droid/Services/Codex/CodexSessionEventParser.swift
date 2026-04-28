import Foundation

enum CodexSessionEventParser {
    struct FileContext: Equatable {
        var originator: String?
        var source: String?
    }

    struct Completion: Equatable {
        let turnID: String
        let message: String
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

        let message = normalizedMessage(payload["last_agent_message"] as? String)
        return Completion(turnID: turnID, message: message)
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
        let cleaned = (message ?? "")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return "Turn completed" }
        return String(cleaned.prefix(200))
    }
}
