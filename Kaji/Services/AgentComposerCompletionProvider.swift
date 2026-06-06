import AppKit
import Foundation

@MainActor
enum AgentComposerCompletionProvider {
    static func state(
        for text: String,
        projectPath: String?,
        slashCommands: [KajiAgentSlashCommand],
        skills: [KajiAgentSkillMetadata],
        history: [KajiAgentHistoryMetadata]
    ) async -> AgentComposerCompletionState {
        if let mention = AskMentionParser.activeMention(in: text), let projectPath {
            let options = await AskMentionSearchService.options(query: mention.query, projectPath: projectPath)
            return completionState(range: mention.range, suggestions: options.map {
                AgentComposerSuggestion(
                    id: "file:\($0.id)",
                    title: $0.path,
                    detail: $0.kind == .folder ? "Folder" : "File",
                    annotation: "@",
                    replacement: "@\($0.path)",
                    kind: .file
                )
            })
        }

        if let token = activeToken(in: text, prefix: "/") {
            return slashState(token: token, slashCommands: slashCommands, skills: skills)
        }

        if let token = activeToken(in: text, prefix: "#") {
            return promptActionState(token: token)
        }

        if let token = activeToken(in: text, prefix: "?") {
            return historyState(token: token, history: history)
        }

        return AgentComposerCompletionState()
    }

    static func apply(_ suggestion: AgentComposerSuggestion, to text: String, state: AgentComposerCompletionState) -> String {
        guard let range = state.triggerRange else { return text }
        var updated = text
        if let replacement = suggestion.replacement {
            updated.replaceSubrange(range, with: replacement)
        }
        if updated.endIndex == updated.startIndex || updated.last?.isWhitespace == false {
            updated.append(" ")
        }
        return updated
    }

    private static func slashState(
        token: ActiveToken,
        slashCommands: [KajiAgentSlashCommand],
        skills: [KajiAgentSkillMetadata]
    ) -> AgentComposerCompletionState {
        let body = String(token.value.dropFirst())
        let parts = body.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        let commandQuery = parts.first.map(String.init) ?? ""
        if parts.count > 1,
           let command = slashCommands.first(where: { $0.name == commandQuery }),
           !command.subcommands.isEmpty
        {
            let argQuery = String(parts[1]).lowercased()
            return completionState(range: token.range, suggestions: command.subcommands.filter {
                argQuery.isEmpty || $0.name.localizedCaseInsensitiveContains(argQuery)
            }.map {
                AgentComposerSuggestion(
                    id: "slash-sub:\(command.name):\($0.name)",
                    title: $0.name,
                    detail: $0.detail,
                    annotation: $0.usage,
                    replacement: "/\(command.name) \($0.name)",
                    kind: .slash,
                    slashName: command.name
                )
            }, inlineHint: command.inlineHint)
        }

        if parts.count > 1 { return AgentComposerCompletionState() }

        let commandSuggestions = slashCommands.compactMap { command -> (AgentComposerSuggestion, Int)? in
            guard let score = slashScore(commandQuery, name: command.name, detail: command.detail, source: command.source)
            else { return nil }
            let suggestion = AgentComposerSuggestion(
                id: "slash:\(command.id)",
                title: "/\(command.name)",
                detail: command.detail,
                annotation: command.source,
                replacement: "/\(command.name)",
                kind: .slash,
                submitOnEnter: true,
                slashName: command.name,
                opensNativePanel: nativePanelCommands.contains(command.name)
            )
            return (suggestion, score)
        }
        .sorted { lhs, rhs in lhs.1 == rhs.1 ? lhs.0.title < rhs.0.title : lhs.1 > rhs.1 }
        .map(\.0)
        let skillSuggestions = skills.compactMap { skill -> (AgentComposerSuggestion, Int)? in
            guard let score = slashScore(commandQuery, name: "skill:\(skill.name)", detail: skill.detail, source: "skill")
            else { return nil }
            return (AgentComposerSuggestion(
                id: "skill:\(skill.id)",
                title: "/skill:\(skill.name)",
                detail: skill.detail,
                annotation: "skill",
                replacement: "/skill:\(skill.name)",
                kind: .skill,
                submitOnEnter: true,
                slashName: "skill:\(skill.name)"
            ), score - 50)
        }
        .sorted { lhs, rhs in lhs.1 == rhs.1 ? lhs.0.title < rhs.0.title : lhs.1 > rhs.1 }
        .map(\.0)
        return completionState(range: token.range, suggestions: commandSuggestions + skillSuggestions)
    }

    private static func promptActionState(token: ActiveToken) -> AgentComposerCompletionState {
        let query = String(token.value.dropFirst())
        let suggestions = promptActions.filter {
            query.isEmpty || fuzzy(query, in: $0.title) || fuzzy(query, in: $0.detail)
        }
        return completionState(range: token.range, suggestions: suggestions)
    }

    private static func historyState(token: ActiveToken, history: [KajiAgentHistoryMetadata]) -> AgentComposerCompletionState {
        let query = String(token.value.dropFirst())
        let suggestions = history.filter {
            query.isEmpty || $0.prompt.localizedCaseInsensitiveContains(query)
        }.map {
            AgentComposerSuggestion(
                id: "history:\($0.id)",
                title: $0.prompt,
                detail: $0.cwd ?? "Recent prompt",
                annotation: "history",
                replacement: $0.prompt,
                kind: .history
            )
        }
        return completionState(range: token.range, suggestions: suggestions)
    }

    private static func activeToken(in text: String, prefix: Character) -> ActiveToken? {
        guard let index = text.lastIndex(of: prefix) else { return nil }
        if index > text.startIndex, !text[text.index(before: index)].isWhitespace { return nil }
        let suffix = text[index...]
        guard !suffix.contains(where: { $0.isWhitespace && prefix != "/" }) else { return nil }
        return ActiveToken(range: index ..< text.endIndex, value: String(suffix))
    }

    private static func completionState(
        range: Range<String.Index>,
        suggestions: [AgentComposerSuggestion],
        inlineHint: String? = nil
    ) -> AgentComposerCompletionState {
        var state = AgentComposerCompletionState()
        state.triggerRange = range
        state.suggestions = Array(suggestions.prefix(12))
        state.inlineHint = inlineHint
        return state
    }

    private static func slashScore(_ query: String, name: String, detail: String, source: String) -> Int? {
        let query = query.lowercased()
        guard !query.isEmpty else { return nativePanelCommands.contains(name) ? 1200 : 1000 }
        let name = name.lowercased()
        let detail = detail.lowercased()
        if name == query { return 2000 }
        if name.hasPrefix(query) { return 1800 - name.count }
        if name.split(whereSeparator: { "-_/:".contains($0) }).contains(where: { $0.hasPrefix(query) }) { return 1600 - name.count }
        if name.contains(query) { return 1300 - name.count }
        if fuzzy(query, in: name) { return 1000 - name.count }
        if detail.contains(query) { return 500 - detail.distance(
            from: detail.startIndex,
            to: detail.range(of: query)?.lowerBound ?? detail.startIndex
        ) }
        if source.contains(query) { return 250 }
        return nil
    }

    private static func fuzzy(_ query: String, in target: String) -> Bool {
        let query = query.lowercased()
        let target = target.lowercased()
        if query.isEmpty { return true }
        if target.contains(query) { return true }
        var index = query.startIndex
        for character in target where index < query.endIndex && character == query[index] {
            index = query.index(after: index)
        }
        return index == query.endIndex
    }

    private static let promptActions: [AgentComposerSuggestion] = [
        AgentComposerSuggestion(
            id: "action:copy-prompt",
            title: "Copy whole prompt",
            detail: "Copy composer text",
            annotation: "#",
            replacement: nil,
            kind: .promptAction
        ),
        AgentComposerSuggestion(
            id: "action:clear",
            title: "Clear prompt",
            detail: "Remove all composer text",
            annotation: "#",
            replacement: "",
            kind: .promptAction
        ),
        AgentComposerSuggestion(
            id: "action:end",
            title: "Move cursor to end",
            detail: "Native text field action",
            annotation: "#",
            replacement: nil,
            kind: .promptAction
        ),
        AgentComposerSuggestion(
            id: "action:start",
            title: "Move cursor to start",
            detail: "Native text field action",
            annotation: "#",
            replacement: nil,
            kind: .promptAction
        ),
    ]

    private static let nativePanelCommands: Set<String> = [
        "model", "models", "settings", "login", "auth", "session", "sessions", "tools", "new", "compact", "handoff", "bash", "ask", "read",
        "bypass",
    ]
}

private struct ActiveToken {
    let range: Range<String.Index>
    let value: String
}
