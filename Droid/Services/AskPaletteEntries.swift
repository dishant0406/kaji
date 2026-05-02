import Foundation

struct AskSlashState: Hashable {
    let token: String
    let command: AskSlashCommand?
    let filter: String
}

enum AskPaletteEntries {
    struct AnnotationContext {
        let active: AskActiveAnnotation
        let provider: AskProvider
        let projects: [Project]
        let worktrees: [Worktree]
        let historyOptions: [AskHistoryOption]
        let skillOptions: [AskSkillOption]
        let taskRecipes: [AskTaskRecipe]
        let directoryOptions: [AskDirectoryOption]
    }

    static func annotationEntries(_ annotation: AnnotationContext) -> [AskPaletteEntry] {
        switch annotation.active.key {
        case .project:
            return filteredProjects(annotation.projects, query: annotation.active.value)
        case .worktree:
            return filteredWorktrees(annotation.worktrees, query: annotation.active.value)
        case .provider:
            return filteredProviders(query: annotation.active.value)
        case .mode:
            return filteredSessionModes(query: annotation.active.value)
        case .history:
            if annotation.provider == .terminal { return [] }
            return filteredHistory(annotation.historyOptions, query: annotation.active.value)
        case .skill:
            if annotation.provider == .terminal { return [] }
            return filteredSkills(annotation.skillOptions, query: annotation.active.value)
        case .task:
            return filteredTasks(annotation.taskRecipes, query: annotation.active.value)
        case .taskAdd:
            return [.init(action: .openTaskForm, title: "Add task", detail: "Create a reusable task prompt", annotation: "Enter")]
        case .taskEdit:
            return filteredEditableTasks(annotation.taskRecipes, query: annotation.active.value)
        case .taskDelete:
            return filteredUserTasks(annotation.taskRecipes, query: annotation.active.value)
        case .projectAdd:
            return directoryEntries(annotation.directoryOptions)
        case .attach:
            return [.init(action: .attach, title: "Attach", detail: "Pick files, folders, or images", annotation: "Enter")]
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
        if AskMentionParser.activeMention(in: context.fieldText) != nil {
            return mentionEntries(context.mentionOptions)
        }
        if let active = parsed.activeAnnotation {
            return annotationEntries(.init(
                active: active,
                provider: context.provider,
                projects: context.projects,
                worktrees: context.worktrees,
                historyOptions: context.historyOptions,
                skillOptions: context.skillOptions,
                taskRecipes: context.taskRecipes,
                directoryOptions: context.directoryOptions
            ))
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
        if !context.fieldText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return [submitEntry(context: context, parsed: parsed)]
        }

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

        return [submitEntry(context: context, parsed: parsed)]
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

    private static func filteredHistory(_ options: [AskHistoryOption], query: String) -> [AskPaletteEntry] {
        options.map { .init(action: .history($0), title: $0.title, detail: $0.detail, annotation: $0.provider.title) }
    }

    private static func filteredTasks(_ recipes: [AskTaskRecipe], query: String) -> [AskPaletteEntry] {
        recipes
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .map { .init(action: .taskRecipe($0), title: $0.name, detail: $0.prompt, annotation: $0.isBuiltIn ? "Built-in" : "Saved") }
    }

    private static func filteredUserTasks(_ recipes: [AskTaskRecipe], query: String) -> [AskPaletteEntry] {
        recipes
            .filter { !$0.isBuiltIn && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }
            .map { .init(action: .deleteTaskRecipe($0), title: $0.name, detail: $0.prompt, annotation: "Delete") }
    }

    private static func filteredEditableTasks(_ recipes: [AskTaskRecipe], query: String) -> [AskPaletteEntry] {
        recipes
            .filter { !$0.isBuiltIn && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }
            .map { .init(action: .editTaskRecipe($0), title: $0.name, detail: $0.prompt, annotation: $0.isGlobal ? "Global" : "Project") }
    }

    private static func mentionEntries(_ options: [AskMentionOption]) -> [AskPaletteEntry] {
        options.map { .init(action: .mention($0), title: $0.title, detail: $0.detail, annotation: $0.kind.rawValue) }
    }

    private static func directoryEntries(_ options: [AskDirectoryOption]) -> [AskPaletteEntry] {
        options.map { .init(action: .directory($0), title: $0.title, detail: $0.detail, annotation: "Shift Enter") }
    }

    private static func filteredSkills(_ options: [AskSkillOption], query: String) -> [AskPaletteEntry] {
        options.map { .init(action: .skill($0), title: $0.name, detail: $0.title, annotation: $0.source) }
    }

    private static func submitEntry(context: AskPaletteContext, parsed: AskParsedInput) -> AskPaletteEntry {
        if let historyID = parsed.annotations[.history],
           let history = context.historyOptions.first(where: { $0.sessionID == historyID })
        {
            return .init(
                action: .submit,
                title: "Resume \(history.title)",
                detail: history.detail,
                annotation: "Enter"
            )
        }
        if let skillName = parsed.annotations[.skill],
           let skill = context.skillOptions.first(where: { $0.name == skillName })
        {
            return .init(
                action: .submit,
                title: "Send to \(context.provider.title) with \(skill.name)",
                detail: skill.title,
                annotation: "Enter"
            )
        }
        let trimmedPrompt = context.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedPrompt.isEmpty {
            return .init(
                action: .launchProvider(context.provider),
                title: "Open \(context.provider.title)",
                detail: routeSummary(
                    sessionMode: context.sessionMode,
                    provider: context.provider,
                    projectName: context.projectName,
                    worktreeName: context.worktreeName,
                    sessions: context.sessions
                ),
                annotation: "Enter"
            )
        }
        return .init(
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
        )
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
