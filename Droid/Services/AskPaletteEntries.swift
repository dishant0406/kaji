import Foundation

struct AskSlashState: Hashable {
    let token: String
    let command: AskSlashCommand?
    let filter: String
}

enum AskPaletteEntries {
    static func annotationEntries(
        active: AskActiveAnnotation,
        projects: [Project],
        worktrees: [Worktree]
    ) -> [AskPaletteEntry] {
        switch active.key {
        case .project:
            filteredProjects(projects, query: active.value)
        case .worktree:
            filteredWorktrees(worktrees, query: active.value)
        case .provider:
            filteredProviders(query: active.value)
        case .session:
            filteredSessionModes(query: active.value)
        }
    }

    static func slashState(for text: String) -> AskSlashState? {
        guard text.hasPrefix("/") else { return nil }
        let body = String(text.dropFirst())
        if body.isEmpty {
            return .init(token: "", command: nil, filter: "")
        }

        let parts = body.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        let token = String(parts[0]).lowercased()
        let filter = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return .init(token: token, command: AskSlashCommand.resolve(token), filter: filter)
    }

    static func build(_ context: AskPaletteContext) -> [AskPaletteEntry] {
        let parsed = AskInlineAnnotations.parse(context.fieldText)
        if let active = parsed.activeAnnotation {
            return annotationEntries(active: active, projects: context.projects, worktrees: context.worktrees)
        }

        if let slashState = slashState(for: context.fieldText) {
            return slashEntries(
                state: slashState,
                projects: context.projects,
                worktrees: context.worktrees
            )
        }

        if context.sessionMode == .existingSession {
            return context.sessions.map {
                .init(
                    action: .session($0),
                    title: $0.title,
                    detail: "\($0.providerTitle) in \($0.worktreeName)",
                    annotation: nil
                )
            }
        }

        let trimmedPrompt = context.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedPrompt.isEmpty {
            return AskSlashCommand.allCases.map { command in
                .init(
                    action: .command(command),
                    title: command.title,
                    detail: currentValue(
                        for: command,
                        projectName: context.projectName,
                        worktreeName: context.worktreeName,
                        provider: context.provider,
                        sessionMode: context.sessionMode
                    ),
                    annotation: command.trigger
                )
            }
        }

        return [
            .init(
                action: .submit,
                title: "Send to \(context.provider.title)",
                detail: routeSummary(
                    sessionMode: context.sessionMode,
                    provider: context.provider,
                    projectName: context.projectName,
                    worktreeName: context.worktreeName,
                    sessions: context.sessions
                ),
                annotation: "Enter"
            ),
        ]
    }

    private static func slashEntries(
        state: AskSlashState,
        projects: [Project],
        worktrees: [Worktree]
    ) -> [AskPaletteEntry] {
        guard let command = state.command, state.token == command.rawValue else {
            return AskSlashCommand.matches(state.token).map {
                .init(action: .command($0), title: $0.title, detail: $0.detail, annotation: $0.trigger)
            }
        }

        switch command {
        case .project:
            return filteredProjects(projects, query: state.filter)
        case .worktree:
            return filteredWorktrees(worktrees, query: state.filter)
        case .provider:
            return filteredProviders(query: state.filter)
        case .session:
            return filteredSessionModes(query: state.filter)
        }
    }

    private static func filteredProjects(_ projects: [Project], query: String) -> [AskPaletteEntry] {
        let filtered = projects.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        return filtered.map { .init(action: .project($0), title: $0.name, detail: $0.path, annotation: nil) }
    }

    private static func filteredWorktrees(_ worktrees: [Worktree], query: String) -> [AskPaletteEntry] {
        let filtered = worktrees.filter { query.isEmpty || AskSessionCatalog.displayName(for: $0).localizedCaseInsensitiveContains(query) }
        return filtered.map {
            .init(action: .worktree($0), title: AskSessionCatalog.displayName(for: $0), detail: $0.path, annotation: $0.branch)
        }
    }

    private static func filteredProviders(query: String) -> [AskPaletteEntry] {
        AskProvider.allCases
            .filter { provider in
                if query.isEmpty {
                    return true
                }
                let normalized = query.lowercased()
                return provider.annotationValue.hasPrefix(normalized) ||
                    provider.rawValue.hasPrefix(normalized) ||
                    provider.title.lowercased().hasPrefix(normalized)
            }
            .map { .init(action: .provider($0), title: $0.title, detail: "Use \($0.title) for new sessions", annotation: nil) }
    }

    private static func filteredSessionModes(query: String) -> [AskPaletteEntry] {
        AskSessionMode.allCases
            .filter { mode in
                if query.isEmpty {
                    return true
                }
                let normalized = query.lowercased()
                return mode.annotationValue.hasPrefix(normalized) ||
                    mode.rawValue.lowercased().hasPrefix(normalized) ||
                    mode.title.lowercased().hasPrefix(normalized)
            }
            .map { .init(action: .sessionMode($0), title: $0.title, detail: sessionModeDetail($0), annotation: nil) }
    }

    private static func currentValue(
        for command: AskSlashCommand,
        projectName: String,
        worktreeName: String,
        provider: AskProvider,
        sessionMode: AskSessionMode
    ) -> String {
        switch command {
        case .project:
            projectName
        case .worktree:
            worktreeName
        case .provider:
            provider.title
        case .session:
            sessionMode.title
        }
    }

    private static func routeSummary(
        sessionMode: AskSessionMode,
        provider: AskProvider,
        projectName: String,
        worktreeName: String,
        sessions: [AskSessionOption]
    ) -> String {
        switch sessionMode {
        case .bestMatch:
            if let session = sessions.first {
                return "Uses \(session.title) in \(projectName)/\(worktreeName)"
            }
            return "Opens a new \(provider.title) session in \(projectName)/\(worktreeName)"
        case .existingSession:
            return "Select a live session below"
        case .newTerminal:
            return "Always opens a new \(provider.title) session in \(projectName)/\(worktreeName)"
        }
    }

    private static func sessionModeDetail(_ mode: AskSessionMode) -> String {
        switch mode {
        case .bestMatch:
            "Reuse a matching session or create one"
        case .existingSession:
            "Send only to a session you choose"
        case .newTerminal:
            "Always open a fresh terminal before sending"
        }
    }
}
