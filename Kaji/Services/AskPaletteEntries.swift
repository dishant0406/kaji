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
        let annotations: [AskAnnotationKey: String]
        let historyOptions: [AskHistoryOption]
        let skillOptions: [AskSkillOption]
        let taskRecipes: [AskTaskRecipe]
        let scripts: [KajiKitScript]
        let bookmarks: [AgentSessionBookmark]
        let bookmarkFolders: [String]
        let directoryOptions: [AskDirectoryOption]
        let diffFiles: [DiffPaletteFile]
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
        case .diff:
            return diffEntries(annotation.diffFiles, query: annotation.active.value)
        case .attach:
            return [.init(action: .attach, title: "Attach", detail: "Pick files, folders, or images", annotation: "Enter")]
        case .execute:
            return filteredScripts(annotation.scripts, query: annotation.active.value).map {
                .init(action: .runScript($0), title: $0.title, detail: scriptDetail($0), annotation: $0.slug)
            }
        case .executeAdd:
            let entry = AskPaletteEntry(
                action: .openScriptForm(nil),
                title: "Add script",
                detail: "Create a KajiKit script in ~/.kajikit",
                annotation: "Enter"
            )
            return [entry]
        case .executeEdit:
            return filteredScripts(annotation.scripts, query: annotation.active.value).map {
                .init(action: .openScriptForm($0), title: $0.title, detail: scriptDetail($0), annotation: $0.slug)
            }
        case .executeDelete:
            return filteredScripts(annotation.scripts, query: annotation.active.value).map {
                .init(action: .deleteScript($0), title: $0.title, detail: scriptDetail($0), annotation: $0.slug)
            }
        case .bookmark:
            return filteredBookmarks(
                annotation.bookmarks,
                folder: annotation.annotations[.bookmarkFolder],
                query: annotation.active.value
            )
        case .bookmarkFolder:
            return filteredBookmarkFolders(annotation.bookmarkFolders, query: annotation.active.value)
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
                annotations: parsed.annotations,
                historyOptions: context.historyOptions,
                skillOptions: context.skillOptions,
                taskRecipes: context.taskRecipes,
                scripts: context.scripts,
                bookmarks: context.bookmarks,
                bookmarkFolders: context.bookmarkFolders,
                directoryOptions: context.directoryOptions,
                diffFiles: context.diffFiles
            ))
        }

        if let slashState = slashState(for: context.fieldText) {
            return slashEntries(
                state: slashState,
                context: context
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
            let commands: [AskPaletteEntry] = AskSlashCommand.allCases.map { command in
                .init(
                    action: .command(command),
                    title: command.title,
                    detail: currentValue(for: command, context: context),
                    annotation: command.trigger
                )
            }
            let sleepEntry = sleepPreventionEntry(
                isEnabled: context.sleepPreventionIsEnabled,
                systemSleepAssertionStatus: context.systemSleepAssertionStatus
            )
            let batteryLidCloseEntry = batteryLidCloseSleepEntry(
                isEnabled: context.batteryLidCloseSleepIsEnabled,
                status: context.batteryLidCloseSleepStatus
            )
            return commands + [sleepEntry, batteryLidCloseEntry]
        }

        return [submitEntry(context: context, parsed: parsed)]
    }

    private static func slashEntries(
        state: AskSlashState,
        context: AskPaletteContext
    ) -> [AskPaletteEntry] {
        guard let command = state.command, state.token == command.rawValue else {
            return AskSlashCommand.matches(state.token).map {
                .init(action: .command($0), title: $0.title, detail: $0.detail, annotation: $0.trigger)
            }
        }

        switch command {
        case .project:
            return filteredProjects(context.projects, query: state.filter)
        case .worktree:
            return filteredWorktrees(context.worktrees, query: state.filter)
        case .provider:
            return filteredProviders(query: state.filter)
        case .session:
            return filteredSessionModes(query: state.filter)
        case .bookmark:
            return bookmarkEntries(
                context.bookmarkCandidates,
                selectedIDs: context.selectedBookmarkIDs,
                isLoading: context.bookmarkLookupIsLoading
            )
        case .sleep:
            let entry = sleepPreventionEntry(
                isEnabled: context.sleepPreventionIsEnabled,
                systemSleepAssertionStatus: context.systemSleepAssertionStatus
            )
            return [entry]
        case .lid:
            let entry = batteryLidCloseSleepEntry(
                isEnabled: context.batteryLidCloseSleepIsEnabled,
                status: context.batteryLidCloseSleepStatus
            )
            return [entry]
        }
    }

    private static func filteredProjects(_ projects: [Project], query: String) -> [AskPaletteEntry] {
        let filtered = projects.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        return filtered.map { .init(action: .project($0), title: $0.name, detail: $0.path, annotation: nil) }
    }

    private static func bookmarkEntries(
        _ candidates: [AgentSessionBookmarkCandidate],
        selectedIDs: Set<UUID>,
        isLoading: Bool
    ) -> [AskPaletteEntry] {
        let loadingEntry = AskPaletteEntry(
            action: .bookmarkLookupLoading,
            title: "Looking for more sessions",
            detail: "Checking Codex and OpenCode history",
            annotation: nil
        )
        if selectedIDs.isEmpty {
            let entries: [AskPaletteEntry] = candidates.map { candidate in
                AskPaletteEntry(
                    action: .bookmarkSession(candidate, selected: false),
                    title: candidate.title,
                    detail: "\(candidate.provider.title) session \(candidate.sessionID)",
                    annotation: "Enter"
                )
            }
            return isLoading ? entries + [loadingEntry] : entries
        }
        let entries = candidates.map { candidate in
            let selected = selectedIDs.contains(candidate.id)
            return AskPaletteEntry(
                action: .bookmarkSession(candidate, selected: selected),
                title: selected ? "✓ \(candidate.title)" : candidate.title,
                detail: "\(candidate.provider.title) session \(candidate.sessionID)",
                annotation: selected ? "Selected" : "Enter"
            )
        }
        let saveEntry = AskPaletteEntry(
            action: .saveSelectedBookmarks,
            title: "Save selected bookmarks",
            detail: "Save \(selectedIDs.count) selected session\(selectedIDs.count == 1 ? "" : "s")",
            annotation: "Shift Enter"
        )
        return entries + (isLoading ? [loadingEntry] : []) + [saveEntry]
    }

    private static func filteredScripts(_ scripts: [KajiKitScript], query: String) -> [KajiKitScript] {
        scripts.filter { script in
            query.isEmpty || script.slug.localizedCaseInsensitiveContains(query) || script.title.localizedCaseInsensitiveContains(query)
        }
    }

    private static func filteredBookmarks(_ bookmarks: [AgentSessionBookmark], folder: String?, query: String) -> [AskPaletteEntry] {
        bookmarks
            .filter { bookmark in
                let folderMatches = folder == nil || bookmark.folderName.compare(
                    folder ?? "",
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) == .orderedSame
                let queryMatches = query.isEmpty || bookmark.title.localizedCaseInsensitiveContains(query) || bookmark.sessionID
                    .localizedCaseInsensitiveContains(query)
                return folderMatches && queryMatches
            }
            .map { bookmark in
                .init(
                    action: .savedBookmark(bookmark),
                    title: bookmark.title,
                    detail: "\(bookmark.providerTitle) · \(bookmark.folderName) · \(bookmark.sessionID)",
                    annotation: "Enter"
                )
            }
    }

    private static func filteredBookmarkFolders(_ folders: [String], query: String) -> [AskPaletteEntry] {
        folders
            .filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
            .map { folder in
                .init(action: .bookmarkFolderFilter(folder), title: folder, detail: "Filter bookmarks by folder", annotation: "Enter")
            }
    }

    private static func scriptDetail(_ script: KajiKitScript) -> String {
        "\(script.scope.rawValue.capitalized) · \(script.kind.rawValue) · \(script.command)"
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

    private static func diffEntries(_ files: [DiffPaletteFile], query: String) -> [AskPaletteEntry] {
        guard let first = files.first else { return [] }
        let filtered = files.filter { file in
            query.isEmpty || file.file.path.localizedCaseInsensitiveContains(query)
        }
        let summary = AskPaletteEntry(
            action: .openDiffSummary(
                projectID: first.projectID,
                worktreeID: first.worktreeID,
                worktreePath: first.worktreePath
            ),
            title: "Open all changes",
            detail: "GitHub-style diff viewer for \(files.count) changed file\(files.count == 1 ? "" : "s")",
            annotation: "Enter"
        )
        let entries = filtered.map { file in
            AskPaletteEntry(
                action: .diffFile(file),
                title: file.file.path,
                detail: diffEntryDetail(file),
                annotation: file.file.paletteAnnotationText
            )
        }
        return query.isEmpty ? [summary] + entries : entries
    }

    private static func diffEntryDetail(_ file: DiffPaletteFile) -> String {
        let stats = file.file.statSummaryText
        guard !stats.isEmpty else { return file.sectionTitle }
        return "\(file.sectionTitle) • \(stats)"
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
        context: AskPaletteContext
    ) -> String {
        switch command {
        case .project:
            context.projectName
        case .worktree:
            context.worktreeName
        case .provider:
            context.provider.title
        case .session:
            context.sessionMode.title
        case .bookmark:
            context.bookmarkCandidates.isEmpty ? "No agent sessions" : "\(context.bookmarkCandidates.count) available"
        case .sleep:
            context.sleepPreventionIsEnabled ? "On" : "Off"
        case .lid:
            context.batteryLidCloseSleepIsEnabled ? "On" : "Off"
        }
    }

    private static func sleepPreventionEntry(
        isEnabled: Bool,
        systemSleepAssertionStatus: SystemSleepAssertionStatus = .inactive
    ) -> AskPaletteEntry {
        .init(
            action: .toggleSleepPrevention,
            title: SleepPreventionDisplayText.title(isEnabled: isEnabled),
            detail: SleepPreventionDisplayText.detail(
                isEnabled: isEnabled,
                systemSleepAssertionStatus: systemSleepAssertionStatus
            ),
            annotation: isEnabled ? "On" : "Off"
        )
    }

    private static func batteryLidCloseSleepEntry(
        isEnabled: Bool,
        status: SystemSleepAssertionStatus = .inactive
    ) -> AskPaletteEntry {
        .init(
            action: .toggleBatteryLidCloseSleepPrevention,
            title: SleepPreventionDisplayText.batteryLidCloseTitle(isEnabled: isEnabled),
            detail: SleepPreventionDisplayText.batteryLidCloseDetail(
                isEnabled: isEnabled,
                status: status
            ),
            annotation: isEnabled ? "On" : "Off"
        )
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
