import Foundation

enum CLILauncherCommandResolver {
    static func resolve(_ command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = parts.first else { return trimmed }
        let executable = String(first)
        guard !executable.contains("/") else { return trimmed }
        guard let resolved = AIProviderExecutableLocator.resolvePath(for: executable) else { return trimmed }
        guard parts.count == 2 else { return ShellEscaper.escape(resolved) }
        return "\(ShellEscaper.escape(resolved)) \(parts[1])"
    }
}
