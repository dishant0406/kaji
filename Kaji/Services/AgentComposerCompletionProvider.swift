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

        let commandSuggestions = slashCommands.filter {
            commandQuery.isEmpty || fuzzy(commandQuery, in: $0.name) || fuzzy(commandQuery, in: $0.detail)
        }.map {
            AgentComposerSuggestion(
                id: "slash:\($0.id)",
                title: "/\($0.name)",
                detail: $0.detail,
                annotation: $0.source,
                replacement: "/\($0.name)",
                kind: .slash,
                submitOnEnter: true,
                slashName: $0.name,
                opensNativePanel: nativePanelCommands.contains($0.name)
            )
        }
        let skillSuggestions = skills.filter {
            commandQuery.isEmpty || fuzzy(commandQuery, in: "skill:\($0.name)") || fuzzy(commandQuery, in: $0.detail)
        }.map {
            AgentComposerSuggestion(
                id: "skill:\($0.id)",
                title: "/skill:\($0.name)",
                detail: $0.detail,
                annotation: "skill",
                replacement: "/skill:\($0.name)",
                kind: .skill,
                submitOnEnter: true,
                slashName: "skill:\($0.name)"
            )
        }
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
        AgentComposerSuggestion(id: "action:copy-prompt", title: "Copy whole prompt", detail: "Copy composer text", annotation: "#", replacement: nil, kind: .promptAction),
        AgentComposerSuggestion(id: "action:clear", title: "Clear prompt", detail: "Remove all composer text", annotation: "#", replacement: "", kind: .promptAction),
        AgentComposerSuggestion(id: "action:end", title: "Move cursor to end", detail: "Native text field action", annotation: "#", replacement: nil, kind: .promptAction),
        AgentComposerSuggestion(id: "action:start", title: "Move cursor to start", detail: "Native text field action", annotation: "#", replacement: nil, kind: .promptAction),
    ]

    private static let nativePanelCommands: Set<String> = [
        "model", "models", "settings", "login", "auth", "session", "sessions", "tools", "new", "compact", "handoff", "bash"
    ]
}

private struct ActiveToken {
    let range: Range<String.Index>
    let value: String
}
