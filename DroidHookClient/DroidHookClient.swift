import Foundation

@main
struct DroidHookClient {
    static func main() {
        var args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else { return }
        args.removeFirst()

        switch command {
        case "send":
            send(args)
        case "ask-complete":
            askComplete(args)
        case "claude-hook":
            claudeHook(event: args.first ?? "", input: stdin())
        case "codex-activity":
            codexActivity(args, input: stdin())
        default:
            return
        }
    }

    private static func send(_ args: [String]) {
        guard args.count >= 3 else { return }
        HookEventEmitter.emit(
            type: args[0],
            paneID: args[1].isEmpty ? nil : args[1],
            title: args[2],
            body: args.count > 3 ? HookTextSanitizer.clean(args[3], limit: 500) : ""
        )
    }

    private static func askComplete(_ args: [String]) {
        guard args.count >= 3 else { return }
        let paneID = ProcessInfo.processInfo.environment["DROID_PANE_ID"]
        guard let paneID, !paneID.isEmpty else { return }
        HookEventEmitter.emit(
            type: args[0],
            paneID: paneID,
            title: args[1],
            body: HookTextSanitizer.clean(args[2], limit: 200)
        )
    }

    private static func claudeHook(event: String, input: String) {
        switch event {
        case "userpromptsubmit":
            HookEventEmitter.emitActivity(provider: "claude", state: "start")
            let keys = ["prompt", "message", "text", "content"]
            HookEventEmitter.emitTranscript(provider: "claude", kind: "user", text: extractedText(input, keys: keys, limit: 500))
        case "permissionrequest":
            HookEventEmitter.emitActivity(provider: "claude", state: "stop")
            emitClaudeNotification(body: "Needs permission")
        case "notification":
            HookEventEmitter.emitActivity(provider: "claude", state: "stop")
            emitClaudeNotification(body: "Needs attention")
        case "stop":
            HookEventEmitter.emitActivity(provider: "claude", state: "stop")
            let body = extractedText(input, keys: ["last_assistant_message", "message", "text", "content"], limit: 200)
            let resolvedBody = body.isEmpty ? "Session completed" : body
            HookEventEmitter.emitTranscript(provider: "claude", kind: "assistant", text: resolvedBody)
            emitClaudeNotification(body: resolvedBody)
        default:
            return
        }
    }

    private static func codexActivity(_ args: [String], input: String) {
        guard args.count >= 2 else { return }
        let provider = args[0]
        let state = args[1]
        guard ["codex", "claude", "opencode"].contains(provider), ["start", "stop"].contains(state) else { return }
        if provider == "codex", let object = HookJSONExtractor.object(from: input), HookJSONExtractor.hasTruthyKey(object, keys: ["agent_id", "agent_type"]) {
            return
        }
        HookEventEmitter.emitActivity(provider: provider, state: state)
        guard provider == "codex", !input.isEmpty else { return }
        let text = extractedText(input, keys: ["prompt", "user_prompt", "last_assistant_message", "message", "text"], limit: 500)
        guard !text.isEmpty else { return }
        HookEventEmitter.emitTranscript(provider: provider, kind: state == "start" ? "user" : "update", text: text)
    }

    private static func emitClaudeNotification(body: String) {
        HookEventEmitter.emit(
            type: "claude_hook",
            paneID: ProcessInfo.processInfo.environment["DROID_PANE_ID"],
            title: "Claude Code",
            body: body
        )
    }

    private static func extractedText(_ input: String, keys: [String], limit: Int) -> String {
        guard let object = HookJSONExtractor.object(from: input) else { return "" }
        return HookTextSanitizer.clean(HookJSONExtractor.firstText(in: object, keys: keys), limit: limit)
    }

    private static func stdin() -> String {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
