import Foundation

enum UserCommandShortcutTemplateParser {
    static func parse(_ source: String) -> UserCommandShortcutTemplateParseResult {
        var parts: [UserCommandShortcutTemplatePart] = []
        var inputVariables: [UserCommandShortcutInputVariable] = []
        var computedVariables: [UserCommandShortcutComputedVariable] = []
        var errors: [UserCommandShortcutTemplateError] = []
        var cursor = source.startIndex

        while let open = source[cursor...].firstIndex(of: "{") {
            if open > cursor {
                parts.append(.literal(String(source[cursor ..< open])))
            }
            guard let close = source[source.index(after: open)...].firstIndex(of: "}") else {
                errors.append(.unclosedPlaceholder)
                return .init(template: nil, errors: errors)
            }
            let rawToken = String(source[source.index(after: open) ..< close])
            appendToken(rawToken, parts: &parts, inputVariables: &inputVariables, computedVariables: &computedVariables, errors: &errors)
            cursor = source.index(after: close)
        }

        if cursor < source.endIndex {
            parts.append(.literal(String(source[cursor...])))
        }
        if usesMixedInputStyles(inputVariables) {
            errors.append(.mixedVariableStyles)
        }
        guard errors.isEmpty else { return .init(template: nil, errors: errors) }
        return .init(
            template: .init(
                source: source,
                parts: parts,
                inputVariables: uniqueInputVariables(inputVariables),
                computedVariables: computedVariables
            ),
            errors: []
        )
    }

    private static func appendToken(
        _ token: String,
        parts: inout [UserCommandShortcutTemplatePart],
        inputVariables: inout [UserCommandShortcutInputVariable],
        computedVariables: inout [UserCommandShortcutComputedVariable],
        errors: inout [UserCommandShortcutTemplateError]
    ) {
        if token.contains("{") || token.contains("}") {
            errors.append(.nestedPlaceholder)
            return
        }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errors.append(.emptyPlaceholder)
            return
        }
        if trimmed.hasPrefix("~") || trimmed.hasSuffix("~") {
            appendComputedToken(trimmed, parts: &parts, computedVariables: &computedVariables, errors: &errors)
            return
        }
        appendInputToken(trimmed, parts: &parts, inputVariables: &inputVariables, errors: &errors)
    }

    private static func appendComputedToken(
        _ token: String,
        parts: inout [UserCommandShortcutTemplatePart],
        computedVariables: inout [UserCommandShortcutComputedVariable],
        errors: inout [UserCommandShortcutTemplateError]
    ) {
        guard token.hasPrefix("~"), token.hasSuffix("~") else {
            errors.append(.invalidVariableName(token))
            return
        }
        let command = token.dropFirst().dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            errors.append(.emptyComputedCommand)
            return
        }
        let variable = UserCommandShortcutComputedVariable(command: command)
        computedVariables.append(variable)
        parts.append(.computed(variable))
    }

    private static func appendInputToken(
        _ token: String,
        parts: inout [UserCommandShortcutTemplatePart],
        inputVariables: inout [UserCommandShortcutInputVariable],
        errors: inout [UserCommandShortcutTemplateError]
    ) {
        let variable: UserCommandShortcutInputVariable?
        if token.allSatisfy(\.isNumber) {
            guard let index = Int(token), index > 0 else {
                errors.append(.invalidPositionalVariable(token))
                return
            }
            variable = .init(token: token, kind: .positional(index))
        } else if isValidNamedVariable(token) {
            variable = .init(token: token, kind: .named(token))
        } else {
            errors.append(.invalidVariableName(token))
            return
        }
        guard let variable else { return }
        inputVariables.append(variable)
        parts.append(.input(variable))
    }

    private static func isValidNamedVariable(_ token: String) -> Bool {
        guard let first = token.unicodeScalars.first, isLetter(first) else { return false }
        return token.unicodeScalars.allSatisfy { isLetter($0) || isDigit($0) || $0.value == 95 }
    }

    private static func usesMixedInputStyles(_ variables: [UserCommandShortcutInputVariable]) -> Bool {
        let hasNamed = variables.contains { variable in
            if case .named = variable.kind { return true }
            return false
        }
        let hasPositional = variables.contains { variable in
            if case .positional = variable.kind { return true }
            return false
        }
        return hasNamed && hasPositional
    }

    private static func uniqueInputVariables(_ variables: [UserCommandShortcutInputVariable]) -> [UserCommandShortcutInputVariable] {
        var seen: Set<String> = []
        return variables.filter { seen.insert($0.token).inserted }
    }

    private static func isLetter(_ scalar: UnicodeScalar) -> Bool {
        scalar.value >= 65 && scalar.value <= 90 || scalar.value >= 97 && scalar.value <= 122
    }

    private static func isDigit(_ scalar: UnicodeScalar) -> Bool {
        scalar.value >= 48 && scalar.value <= 57
    }
}
