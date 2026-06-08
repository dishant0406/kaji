import Foundation

struct UserCommandShortcutState: Hashable {
    let slug: String
    let rawArguments: String
    let arguments: [String]
    let argumentError: String?
}

enum UserCommandShortcutParser {
    static func state(for text: String) -> UserCommandShortcutState? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("::") else { return nil }
        let body = String(trimmed.dropFirst(2))
        let parts = body.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        let slug = parts.first.map(String.init) ?? ""
        let rawArguments = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        do {
            let arguments = try GitCommandParser.arguments(from: rawArguments)
            return UserCommandShortcutState(
                slug: UserCommandShortcutValidator.slug(from: slug),
                rawArguments: rawArguments,
                arguments: arguments,
                argumentError: nil
            )
        } catch {
            return UserCommandShortcutState(
                slug: UserCommandShortcutValidator.slug(from: slug),
                rawArguments: rawArguments,
                arguments: [],
                argumentError: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }
}
