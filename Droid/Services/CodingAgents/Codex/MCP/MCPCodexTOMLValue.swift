import Foundation

enum MCPCodexTOMLValue {
    static func tableName(from line: String) -> String? {
        guard line.hasPrefix("["), line.hasSuffix("]") else { return nil }
        return String(line.dropFirst().dropLast())
    }

    static func assignment(from line: String) -> (key: String, value: String)? {
        let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        return (String(parts[0]).trimmingCharacters(in: .whitespaces), String(parts[1]).trimmingCharacters(in: .whitespaces))
    }

    static func parseString(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, trimmed.first == "\"", trimmed.last == "\"" else { return trimmed }
        return String(trimmed.dropFirst().dropLast())
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    static func parseArray(_ value: String) -> [String] {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else { return [] }
        return splitComma(String(trimmed.dropFirst().dropLast())).map(parseString)
    }

    static func parseInlineTable(_ value: String) -> [String: String] {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else { return [:] }
        return splitComma(String(trimmed.dropFirst().dropLast())).reduce(into: [String: String]()) { result, entry in
            guard let assignment = assignment(from: entry) else { return }
            result[assignment.key.trimmingCharacters(in: CharacterSet(charactersIn: "\""))] = parseString(assignment.value)
        }
    }

    static func parseBool(_ value: String) -> Bool? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "true": true
        case "false": false
        default: nil
        }
    }

    static func inlineTable(_ values: [String: String]) -> String {
        values.keys.sorted().map { "\($0) = \"\(escape(values[$0] ?? ""))\"" }.joined(separator: ", ")
    }

    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func splitComma(_ value: String) -> [String] {
        var result = [String]()
        var current = ""
        var inString = false
        var escaping = false
        for character in value {
            if escaping {
                current.append(character)
                escaping = false
                continue
            }
            if character == "\\" {
                current.append(character)
                escaping = true
                continue
            }
            if character == "\"" { inString.toggle() }
            if character == ",", !inString {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        let tail = current.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { result.append(tail) }
        return result
    }
}
