import Foundation

enum ClaudeHookHandler {
    static func handle(event: String, input: String) {
        HookEventEmitter.emitSession(provider: "claude", input: input, source: event)
        switch event {
        case "userpromptsubmit":
            HookEventEmitter.emitActivity(provider: "claude", state: "start")
            let keys = ["prompt", "message", "text", "content"]
            HookEventEmitter.emitTranscript(provider: "claude", kind: "user", text: extractedText(input, keys: keys, limit: 500))
        case "permissionrequest":
            let detail = extractedText(input, keys: ["tool_name", "tool", "command", "path", "reason", "message"], limit: 200)
            HookEventEmitter.emit(
                type: "claude_attention",
                paneID: ProcessInfo.processInfo.environment["DROID_PANE_ID"],
                title: "permission",
                body: detail.isEmpty ? "Needs permission" : detail
            )
            emitNotification(body: detail.isEmpty ? "Needs permission" : "Needs permission: \(detail)")
        case "notification":
            HookEventEmitter.emit(
                type: "claude_attention",
                paneID: ProcessInfo.processInfo.environment["DROID_PANE_ID"],
                title: "question",
                body: "Needs attention"
            )
            emitNotification(body: "Needs attention")
        case "stop":
            HookEventEmitter.emitActivity(provider: "claude", state: "stop")
            let body = extractedText(input, keys: ["last_assistant_message", "message", "text", "content"], limit: 200)
            let resolvedBody = body.isEmpty ? "Session completed" : body
            HookEventEmitter.emitTranscript(provider: "claude", kind: "assistant", text: resolvedBody)
            emitNotification(body: resolvedBody)
        default:
            return
        }
    }

    private static func emitNotification(body: String) {
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
}
