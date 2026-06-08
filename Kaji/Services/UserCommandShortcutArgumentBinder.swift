import Foundation

enum UserCommandShortcutArgumentBinder {
    static func validationMessage(template: UserCommandShortcutTemplate, arguments: [String]) -> String? {
        guard !template.inputVariables.isEmpty else {
            return arguments.isEmpty ? nil : "This command shortcut does not accept values."
        }
        let required = requiredArgumentCount(template.inputVariables)
        if arguments.count < required {
            let missing = missingVariables(template.inputVariables, argumentCount: arguments.count).joined(separator: ", ")
            return missing.isEmpty ? "Missing required values." : "Needs \(missing)."
        }
        if arguments.count > required {
            return "Expected \(required) value\(required == 1 ? "" : "s"), got \(arguments.count)."
        }
        return nil
    }

    static func bindings(template: UserCommandShortcutTemplate, arguments: [String]) -> [String: String] {
        var result: [String: String] = [:]
        for variable in template.inputVariables {
            switch variable.kind {
            case .named:
                guard let index = template.inputVariables.firstIndex(of: variable), index < arguments.count else { continue }
                result[variable.token] = arguments[index]
            case let .positional(index):
                guard index <= arguments.count else { continue }
                result[variable.token] = arguments[index - 1]
            }
        }
        return result
    }

    private static func requiredArgumentCount(_ variables: [UserCommandShortcutInputVariable]) -> Int {
        variables.map { variable in
            switch variable.kind {
            case .named:
                1
            case let .positional(index):
                index
            }
        }.max() ?? 0
    }

    private static func missingVariables(_ variables: [UserCommandShortcutInputVariable], argumentCount: Int) -> [String] {
        variables.compactMap { variable in
            switch variable.kind {
            case .named:
                guard let index = variables.firstIndex(of: variable), index >= argumentCount else { return nil }
                return variable.displayName
            case let .positional(index):
                return index > argumentCount ? variable.displayName : nil
            }
        }
    }
}
