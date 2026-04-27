import Foundation

enum GhosttyPerformanceDefaults {
    private static let scrollbackLimitKey = "scrollback-limit"
    private static let defaultScrollbackLimit = 5_000_000

    static func linesIfMissing(in lines: [String]) -> [String] {
        guard !hasConfigLine(for: scrollbackLimitKey, in: lines) else { return [] }
        return ["scrollback-limit = \(defaultScrollbackLimit)"]
    }

    private static func hasConfigLine(for key: String, in lines: [String]) -> Bool {
        lines.contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(key) else { return false }
            let suffix = trimmed.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
            return suffix.hasPrefix("=")
        }
    }
}
