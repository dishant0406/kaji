import Foundation

enum GoToLineParser {
    static func parse(_ input: String) -> EditorLineNavigationRequest? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard let line = parsePositive(parts.first.map(String.init)) else { return nil }
        let column = parts.count > 1 ? parsePositive(String(parts[1])) ?? 1 : 1
        return EditorLineNavigationRequest(line: line, column: column)
    }

    private static func parsePositive(_ value: String?) -> Int? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = Int(trimmed), number > 0 else { return nil }
        return number
    }
}
