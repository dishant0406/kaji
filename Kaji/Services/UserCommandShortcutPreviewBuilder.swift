import Foundation

enum UserCommandShortcutPreviewBuilder {
    static func preview(shortcut: UserCommandShortcut, state: UserCommandShortcutState) -> UserCommandShortcutPreview {
        if let argumentError = state.argumentError {
            return .init(detail: argumentError, annotation: "Invalid")
        }
        let parsed = UserCommandShortcutTemplateParser.parse(shortcut.command)
        guard let template = parsed.template else {
            return .init(detail: parsed.errors.first?.message ?? "Invalid command template", annotation: "Invalid")
        }
        if let message = UserCommandShortcutArgumentBinder.validationMessage(template: template, arguments: state.arguments) {
            return .init(detail: message, annotation: "Missing")
        }
        return .init(detail: renderedPreview(template: template, arguments: state.arguments), annotation: "Enter")
    }

    private static func renderedPreview(template: UserCommandShortcutTemplate, arguments: [String]) -> String {
        let bindings = UserCommandShortcutArgumentBinder.bindings(template: template, arguments: arguments)
        return template.parts.map { part in
            switch part {
            case let .literal(text):
                text
            case let .input(variable):
                bindings[variable.token] ?? "{\(variable.displayName)}"
            case let .computed(variable):
                "{~\(variable.command)~}"
            }
        }.joined()
    }
}
