import Foundation

struct UserCommandShortcutTemplate: Hashable {
    let source: String
    let parts: [UserCommandShortcutTemplatePart]
    let inputVariables: [UserCommandShortcutInputVariable]
    let computedVariables: [UserCommandShortcutComputedVariable]
}

enum UserCommandShortcutTemplatePart: Hashable {
    case literal(String)
    case input(UserCommandShortcutInputVariable)
    case computed(UserCommandShortcutComputedVariable)
}

struct UserCommandShortcutInputVariable: Hashable {
    let token: String
    let kind: UserCommandShortcutInputVariableKind

    var displayName: String {
        switch kind {
        case let .named(name):
            name
        case let .positional(index):
            String(index)
        }
    }
}

enum UserCommandShortcutInputVariableKind: Hashable {
    case named(String)
    case positional(Int)
}

struct UserCommandShortcutComputedVariable: Hashable {
    let command: String
}

enum UserCommandShortcutTemplateError: Hashable {
    case unclosedPlaceholder
    case nestedPlaceholder
    case emptyPlaceholder
    case invalidVariableName(String)
    case invalidPositionalVariable(String)
    case emptyComputedCommand
    case mixedVariableStyles

    var message: String {
        switch self {
        case .unclosedPlaceholder:
            "Command has an unclosed variable placeholder."
        case .nestedPlaceholder:
            "Nested variable placeholders are not supported."
        case .emptyPlaceholder:
            "Variable placeholders cannot be empty."
        case let .invalidVariableName(name):
            "Invalid variable name \"\(name)\". Use letters, numbers, and underscores."
        case let .invalidPositionalVariable(name):
            "Invalid positional variable \"\(name)\". Use {1}, {2}, and higher."
        case .emptyComputedCommand:
            "Computed variables need a command between ~ markers."
        case .mixedVariableStyles:
            "Use either named variables or positional variables, not both."
        }
    }
}

struct UserCommandShortcutTemplateParseResult: Hashable {
    let template: UserCommandShortcutTemplate?
    let errors: [UserCommandShortcutTemplateError]
}
