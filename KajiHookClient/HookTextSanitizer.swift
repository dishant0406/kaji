import Foundation

enum HookTextSanitizer {
    static func clean(_ value: String?, limit: Int = 500) -> String {
        let cleaned = (value ?? "")
            .replacingOccurrences(of: "|", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return String(cleaned.prefix(limit))
    }
}
