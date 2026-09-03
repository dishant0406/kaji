import Foundation

enum KajiCodeHookHandler {
    static func handle(event: String, input: String) {
        let event = resolvedEvent(event: event, input: input)
        HookEventEmitter.emitSession(provider: "kajicode", input: input, source: event)
        switch event {
        case "sessionStart":
            HookEventEmitter.emitActivity(provider: "kajicode", state: "start", input: input)
            emitTranscript(kind: "user", input: input, keys: ["sessionTitle", "tag", "model"])
        case "sessionEnd":
            HookEventEmitter.emitActivity(provider: "kajicode", state: "stop", input: input)
            emitTranscript(kind: "assistant", input: input, keys: ["finishReason", "stopReason", "error"])
            emitCompletion(input: input)
        case "beforeTool",
             "afterTool",
             "specialistStart",
             "specialistStop":
            HookEventEmitter.emitActivity(provider: "kajicode", state: "observe", input: input)
        default:
            return
        }
    }

    private static func resolvedEvent(event: String, input: String) -> String {
        let trimmed = event.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        guard let object = HookJSONExtractor.object(from: input),
              let value = object["event"] as? String
        else { return "" }
        return value
    }

    private static func emitCompletion(input: String) {
        let body = extractedText(input, keys: ["error", "finishReason", "stopReason"], limit: 300)
        HookEventEmitter.emit(
            type: "kajicode",
            paneID: ProcessInfo.processInfo.environment["KAJI_PANE_ID"],
            title: "KajiCode",
            body: body.isEmpty ? "Session completed" : body
        )
    }

    private static func emitTranscript(kind: String, input: String, keys: [String]) {
        let text = extractedText(input, keys: keys, limit: 500)
        guard !text.isEmpty else { return }
        HookEventEmitter.emitTranscript(provider: "kajicode", kind: kind, text: text)
    }

    private static func extractedText(_ input: String, keys: [String], limit: Int) -> String {
        guard let object = HookJSONExtractor.object(from: input) else { return "" }
        return HookTextSanitizer.clean(HookJSONExtractor.firstText(in: object, keys: keys), limit: limit)
    }
}
