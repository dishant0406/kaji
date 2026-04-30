import Foundation

enum AskProvider: String, CaseIterable, Hashable, Identifiable {
    case terminal
    case codex
    case claude
    case opencode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terminal:
            "Terminal"
        case .codex:
            "Codex"
        case .claude:
            "Claude Code"
        case .opencode:
            "OpenCode"
        }
    }

    var annotationValue: String {
        switch self {
        case .terminal:
            "terminal"
        case .codex:
            "codex"
        case .claude:
            "claude"
        case .opencode:
            "opencode"
        }
    }

    var commandTitle: String {
        switch self {
        case .terminal:
            "Terminal"
        case .codex:
            "Codex"
        case .claude:
            "Claude Code"
        case .opencode:
            "OpenCode"
        }
    }

    var launcherID: String? {
        switch self {
        case .terminal:
            nil
        case .codex:
            "codex"
        case .claude:
            "claude"
        case .opencode:
            "opencode"
        }
    }

    func matches(title: String) -> Bool {
        switch self {
        case .terminal:
            Self.detect(from: title) == .terminal
        default:
            Self.detect(from: title) == self
        }
    }

    static func detect(from title: String) -> Self {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "codex" || normalized.hasPrefix("codex ") {
            return .codex
        }
        if normalized == "claude code" || normalized == "claude" || normalized.hasPrefix("claude code ") {
            return .claude
        }
        if normalized == "opencode" || normalized.hasPrefix("opencode ") {
            return .opencode
        }
        return .terminal
    }

    static func detect(
        title: String,
        startupCommand: String?,
        injectedCommand: String?,
        processNames: [String] = []
    ) -> Self {
        let fromTitle = detect(from: title)
        if fromTitle != .terminal {
            return fromTitle
        }

        let candidates = [startupCommand, injectedCommand].compactMap { commandBase(from: $0) } + processNames
        for candidate in candidates {
            let normalized = candidate.lowercased()
            if normalized == "codex" {
                return .codex
            }
            if normalized == "claude" || normalized == "claude-code" {
                return .claude
            }
            if normalized == "opencode" {
                return .opencode
            }
        }

        return .terminal
    }

    static func resolveAnnotation(_ value: String) -> Self? {
        let normalized = value.lowercased()
        return allCases.first { provider in
            provider.annotationValue == normalized ||
                provider.rawValue == normalized ||
                provider.title.lowercased() == normalized ||
                (provider == .claude && ["claude-code", "claudecode"].contains(normalized)) ||
                (provider == .terminal && ["term", "shell"].contains(normalized))
        }
    }

    private static func commandBase(from command: String?) -> String? {
        guard let command else { return nil }
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let firstToken = trimmed.split(whereSeparator: \.isWhitespace).first else { return nil }
        let token = String(firstToken).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return URL(fileURLWithPath: token).lastPathComponent
    }
}
