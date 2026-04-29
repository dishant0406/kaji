import Foundation

struct AskSlashState: Hashable {
    let token: String
    let command: AskSlashCommand?
    let filter: String
}

enum AskPaletteEntries {
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

    static func build(
        fieldText: String,
        prompt: String,
        projects: [Project],
        worktrees: [Worktree],
        provider: AskProvider,
        sessionMode: AskSessionMode,
        sessions: [AskSessionOption],
        projectName: String,
        worktreeName: String
    ) -> [AskPaletteEntry] {
        if let slashState = slashState(for: fieldText) {
            return slashEntries(
                state: slashState,
                projects: projects,
                worktrees: worktrees
            )
        }

        if sessionMode == .existingSession {
            return sessions.map {
                .init(
                    action: .session($0),
                    title: $0.title,
                    detail: "\($0.providerTitle) in \($0.worktreeName)",
                    annotation: nil
                )
            }
        }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedPrompt.isEmpty {
            return AskSlashCommand.allCases.map { command in
                .init(
                    action: .command(command),
                    title: command.title,
                    detail: currentValue(for: command, projectName: projectName, worktreeName: worktreeName, provider: provider, sessionMode: sessionMode),
                    annotation: command.trigger
                )
            }
        }

        return [
            .init(
                action: .submit,
                title: "Send to \(provider.title)",
                detail: routeSummary(
                    sessionMode: sessionMode,
                    provider: provider,
                    projectName: projectName,
                    worktreeName: worktreeName,
                    sessions: sessions
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
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.rawValue.localizedCaseInsensitiveContains(query) }
            .map { .init(action: .provider($0), title: $0.title, detail: "Use \($0.title) for new sessions", annotation: nil) }
    }

    private static func filteredSessionModes(query: String) -> [AskPaletteEntry] {
        AskSessionMode.allCases
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
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
