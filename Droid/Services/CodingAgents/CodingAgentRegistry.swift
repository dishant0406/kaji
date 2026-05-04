import Foundation

final class CodingAgentRegistry: @unchecked Sendable {
    static let shared = CodingAgentRegistry()

    private let codex = CodexAgentModule()
    private let claude = ClaudeCodeAgentModule()
    private let openCode = OpenCodeAgentModule()
    private let pi = PiAgentModule()

    lazy var agents: [any CodingAgentModule] = [
        codex,
        claude,
        openCode,
        pi,
    ]

    private init() {}

    var definitions: [CodingAgentDefinition] {
        agents.map(\.definition)
    }

    func agent(id: String) -> (any CodingAgentModule)? {
        agents.first { $0.id == id }
    }

    func definition(id: String) -> CodingAgentDefinition? {
        agent(id: id)?.definition
    }

    func resolve(_ value: String) -> CodingAgentDefinition? {
        definitions.first { $0.matches(value) }
    }

    func detect(title: String, startupCommand: String?, injectedCommand: String?, processNames: [String]) -> CodingAgentDefinition? {
        let titleValue = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let titleMatch = definitions.first(where: { matchesTitle($0, titleValue: titleValue) }) {
            return titleMatch
        }

        let candidates = [startupCommand, injectedCommand].compactMap(commandBase(from:)) + processNames
        return candidates.compactMap { candidate in
            definitions.first { $0.executableNames.contains(candidate.lowercased()) || $0.matches(candidate) }
        }.first
    }

    private func commandBase(from command: String?) -> String? {
        guard let command else { return nil }
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let firstToken = trimmed.split(whereSeparator: \.isWhitespace).first else { return nil }
        let token = String(firstToken).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return URL(fileURLWithPath: token).lastPathComponent.lowercased()
    }

    private func matchesTitle(_ definition: CodingAgentDefinition, titleValue: String) -> Bool {
        let displayName = definition.displayName.lowercased()
        return titleValue == displayName ||
            titleValue.hasPrefix(displayName + " ") ||
            titleValue == definition.id ||
            titleValue.hasPrefix(definition.id + " ")
    }
}
