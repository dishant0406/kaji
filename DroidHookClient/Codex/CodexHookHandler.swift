import Foundation

enum CodexHookHandler {
    static func handle(args: [String], input: String) {
        guard args.count >= 2 else { return }
        let provider = args[0]
        let state = args[1]
        guard !provider.isEmpty, ["start", "stop", "attention"].contains(state) else { return }
        if shouldIgnoreNestedCodex(provider: provider, input: input) { return }
        HookEventEmitter.emitSession(provider: provider, input: input, source: state)
        if state == "attention" {
            emitAttention(provider: provider, input: input)
            return
        }
        HookEventEmitter.emitActivity(provider: provider, state: state)
        guard provider == "codex" else { return }
        emitTranscript(provider: provider, state: state, input: input)
    }

    private static func shouldIgnoreNestedCodex(provider: String, input: String) -> Bool {
        provider == "codex"
            && HookJSONExtractor.object(from: input).map {
                HookJSONExtractor.hasTruthyKey($0, keys: ["agent_id", "agent_type"])
            } == true
    }

    private static func emitAttention(provider: String, input: String) {
        let detail = extractedText(input, keys: ["tool_name", "tool", "command", "path", "reason", "message"], limit: 500)
        let body = detail.isEmpty ? "Needs permission" : "Needs permission: \(detail)"
        HookEventEmitter.emit(
            type: "\(provider)_attention",
            paneID: ProcessInfo.processInfo.environment["DROID_PANE_ID"],
            title: "permission",
            body: body
        )
        HookEventEmitter.emit(
            type: provider,
            paneID: ProcessInfo.processInfo.environment["DROID_PANE_ID"],
            title: "permission",
            body: body
        )
    }

    private static func emitTranscript(provider: String, state: String, input: String) {
        guard !input.isEmpty else { return }
        let text = extractedText(input, keys: ["prompt", "user_prompt", "last_assistant_message", "message", "text"], limit: 500)
        guard !text.isEmpty else { return }
        HookEventEmitter.emitTranscript(provider: provider, kind: state == "start" ? "user" : "update", text: text)
    }

    private static func extractedText(_ input: String, keys: [String], limit: Int) -> String {
        guard let object = HookJSONExtractor.object(from: input) else { return "" }
        return HookTextSanitizer.clean(HookJSONExtractor.firstText(in: object, keys: keys), limit: limit)
    }
}
