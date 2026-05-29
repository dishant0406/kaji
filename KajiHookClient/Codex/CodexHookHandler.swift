import Foundation

enum CodexHookHandler {
    static func handle(args: [String], input: String) {
        guard args.count >= 2 else { return }
        let provider = args[0]
        let parsed = parse(args: args, input: input)
        guard !provider.isEmpty, ["start", "stop", "attention", "observe"].contains(parsed.action) else { return }
        if shouldIgnoreNestedCodex(provider: provider, input: input) { return }
        HookEventEmitter.emitSession(provider: provider, input: input, source: parsed.eventName)
        if parsed.action == "attention" {
            emitAttention(provider: provider, input: input)
            return
        }
        if parsed.action == "observe" {
            return
        }
        HookEventEmitter.emitActivity(provider: provider, state: parsed.action, input: input)
        guard provider == "codex" else { return }
        emitTranscript(provider: provider, action: parsed.action, eventName: parsed.eventName, input: input)
        if parsed.action == "stop" {
            emitCompletion(provider: provider, input: input)
        }
    }

    private static func parse(args: [String], input: String) -> (eventName: String, action: String) {
        if args.count >= 3 {
            return (args[1], args[2])
        }
        let action = args[1]
        let eventName = extractedText(input, keys: ["hook_event_name"], limit: 100)
        return (eventName.isEmpty ? action : eventName, action)
    }

    private static func shouldIgnoreNestedCodex(provider: String, input: String) -> Bool {
        provider == "codex"
            && HookJSONExtractor.object(from: input).map {
                HookJSONExtractor.hasTruthyKey($0, keys: ["agent_id", "agent_type"])
            } == true
    }

    private static func emitAttention(provider: String, input: String) {
        let detail = extractedText(input, keys: ["description", "tool_name", "tool", "command", "path", "reason", "message"], limit: 500)
        let body = detail.isEmpty ? "Needs permission" : "Needs permission: \(detail)"
        HookEventEmitter.emit(
            type: "\(provider)_attention",
            paneID: ProcessInfo.processInfo.environment["KAJI_PANE_ID"],
            title: "permission",
            body: body
        )
        HookEventEmitter.emit(
            type: provider,
            paneID: ProcessInfo.processInfo.environment["KAJI_PANE_ID"],
            title: "permission",
            body: body
        )
    }

    private static func emitCompletion(provider: String, input: String) {
        let body = extractedText(input, keys: ["last_assistant_message", "message", "text"], limit: 500)
        HookEventEmitter.emit(
            type: provider,
            paneID: ProcessInfo.processInfo.environment["KAJI_PANE_ID"],
            title: "Codex",
            body: body.isEmpty ? "Turn completed" : body
        )
    }

    private static func emitTranscript(provider: String, action: String, eventName: String, input: String) {
        guard !input.isEmpty else { return }
        let keys = action == "stop" ? ["last_assistant_message", "message", "text"] : ["prompt", "user_prompt", "message", "text"]
        let text = extractedText(input, keys: keys, limit: 500)
        guard !text.isEmpty else { return }
        let kind = action == "stop" ? "assistant" : eventName.lowercased() == "userpromptsubmit" ? "user" : "update"
        HookEventEmitter.emitTranscript(provider: provider, kind: kind, text: text)
    }

    private static func extractedText(_ input: String, keys: [String], limit: Int) -> String {
        guard let object = HookJSONExtractor.object(from: input) else { return "" }
        return HookTextSanitizer.clean(HookJSONExtractor.firstText(in: object, keys: keys), limit: limit)
    }
}
