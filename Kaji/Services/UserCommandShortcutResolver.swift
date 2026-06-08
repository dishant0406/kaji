import Foundation

enum UserCommandShortcutResolver {
    typealias ComputedValueRunner = (String, URL) async -> UserCommandShortcutComputedValueResult

    static func resolve(
        shortcut: UserCommandShortcut,
        state: UserCommandShortcutState,
        workingDirectory: URL,
        computedValueRunner: @escaping ComputedValueRunner = { command, workingDirectory in
            await UserCommandShortcutComputedValueRunner.run(command: command, workingDirectory: workingDirectory)
        }
    ) async -> UserCommandShortcutResolveResult {
        if let argumentError = state.argumentError {
            return .failure(title: "::\(shortcut.slug)", message: argumentError)
        }
        let parsed = UserCommandShortcutTemplateParser.parse(shortcut.command)
        guard let template = parsed.template else {
            return .failure(title: "::\(shortcut.slug)", message: parsed.errors.map(\.message).joined(separator: "\n"))
        }
        if let message = UserCommandShortcutArgumentBinder.validationMessage(template: template, arguments: state.arguments) {
            return .failure(title: "::\(shortcut.slug)", message: message)
        }
        let rendered = await render(
            template: template,
            state: state,
            workingDirectory: workingDirectory,
            computedValueRunner: computedValueRunner
        )
        switch rendered {
        case let .success(command):
            return .plan(.init(
                title: "::\(shortcut.slug) -> \(command)",
                executable: "/bin/zsh",
                arguments: ["-lc", command],
                workingDirectory: workingDirectory,
                refreshesRepository: false
            ))
        case let .failure(message):
            return .failure(title: "::\(shortcut.slug)", message: message)
        }
    }

    private static func render(
        template: UserCommandShortcutTemplate,
        state: UserCommandShortcutState,
        workingDirectory: URL,
        computedValueRunner: @escaping ComputedValueRunner
    ) async -> UserCommandShortcutComputedValueResult {
        let inputBindings = UserCommandShortcutArgumentBinder.bindings(template: template, arguments: state.arguments)
        var computedBindings: [String: String] = [:]
        var output = ""
        for part in template.parts {
            switch part {
            case let .literal(text):
                output += text
            case let .input(variable):
                output += ShellEscaper.escape(inputBindings[variable.token] ?? "")
            case let .computed(variable):
                let value: String
                if let cached = computedBindings[variable.command] {
                    value = cached
                } else {
                    switch await computedValueRunner(variable.command, workingDirectory) {
                    case let .success(result):
                        value = result
                        computedBindings[variable.command] = result
                    case let .failure(message):
                        return .failure("Computed variable failed: \(variable.command)\n\(message)")
                    }
                }
                output += ShellEscaper.escape(value)
            }
        }
        return .success(output)
    }
}
