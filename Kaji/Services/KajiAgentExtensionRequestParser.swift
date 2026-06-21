import Foundation

enum KajiAgentExtensionRequestParser {
    static func actions(for frame: KajiAgentRPCFrame) -> [KajiAgentExtensionRequestAction] {
        guard let id = frame.id, let method = frame.method else { return [] }
        switch method {
        case "select":
            return [
                .question(KajiAgentQuestion(
                    id: id,
                    title: frame.title ?? "Choose an option",
                    method: method,
                    options: frame.options ?? []
                )),
            ]
        case "confirm":
            if let request = KajiAgentApprovalRequest.fromConfirm(id: id, title: frame.title, message: frame.message) {
                return [.approval(request)]
            }
            return [
                .question(KajiAgentQuestion(
                    id: id,
                    title: frame.title ?? frame.message ?? "Confirm",
                    method: method,
                    options: ["Confirm", "Cancel"]
                )),
            ]
        case "input",
             "editor":
            return [
                .question(KajiAgentQuestion(
                    id: id,
                    title: frame.title ?? "Kaji needs input",
                    method: method,
                    placeholder: frame.placeholder,
                    prefill: frame.prefill,
                    promptStyle: frame.promptStyle ?? false,
                    isSecure: frame.isSecure ?? false,
                    allowEmpty: frame.allowEmpty ?? false,
                    timeout: frame.timeout,
                    options: []
                )),
            ]
        case "cancel":
            guard let targetID = frame.targetId else { return [] }
            return [.clearQuestion(targetID)]
        case "notify":
            let isError = frame.notifyType == "error"
            return [
                .system(
                    title: isError ? "Error" : "Notice",
                    detail: frame.message ?? "",
                    kind: isError ? .error : .event
                ),
            ]
        case "open_url":
            let display = KajiAgentLoginDisplay(
                url: frame.url,
                instructions: frame.instructions ?? frame.url,
                code: KajiAgentLoginCodeExtractor.extract(from: frame.instructions),
                status: frame.instructions ?? "Open browser to continue."
            )
            return [
                .loginDisplay(display),
                .openURL(frame.url),
                .system(title: "Login", detail: frame.instructions ?? frame.url ?? "Opened browser", kind: .event),
            ]
        case "setWidget":
            return [
                .widget(
                    key: frame.widgetKey ?? "default",
                    lines: frame.widgetLines,
                    placement: frame.widgetPlacement
                ),
            ]
        case "setStatus":
            return [.status(key: frame.statusKey ?? "default", text: frame.statusText)]
        case "set_editor_text":
            return [
                .editorQuestion(KajiAgentQuestion(
                    id: id,
                    title: "Runtime updated editor text",
                    method: method,
                    prefill: frame.text,
                    options: []
                )),
            ]
        case "setTitle":
            guard let title = frame.title else { return [] }
            return [.title(title)]
        default:
            return []
        }
    }
}

enum KajiAgentExtensionRequestAction: Equatable {
    case question(KajiAgentQuestion)
    case approval(KajiAgentApprovalRequest)
    case clearQuestion(String)
    case system(title: String, detail: String, kind: KajiAgentMessageKind)
    case loginDisplay(KajiAgentLoginDisplay)
    case openURL(String?)
    case widget(key: String, lines: [String]?, placement: String?)
    case status(key: String, text: String?)
    case editorQuestion(KajiAgentQuestion)
    case title(String)
}

struct KajiAgentLoginDisplay: Equatable {
    let url: String?
    let instructions: String?
    let code: String?
    let status: String
}

enum KajiAgentLoginCodeExtractor {
    static func extract(from instructions: String?) -> String? {
        guard let instructions else { return nil }
        let pattern = #"(?i)(?:enter\s+code|code)[:\s]+([A-Z0-9\-]{4,})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: instructions, range: NSRange(instructions.startIndex..., in: instructions)),
              let range = Range(match.range(at: 1), in: instructions)
        else { return nil }
        return String(instructions[range])
    }
}
