import SwiftUI

extension AskOverlay {
    var parsedInput: AskParsedInput {
        AskInlineAnnotations.parse(fieldText)
    }

    var entries: [AskPaletteEntry] {
        AskPaletteEntries.build(.init(
            fieldText: fieldText,
            prompt: prompt,
            projects: projectStore.projects,
            worktrees: availableWorktrees,
            provider: provider,
            sessionMode: sessionMode,
            sessions: filteredSessions,
            historyOptions: historyOptions,
            skillOptions: skillOptions,
            projectName: selectedProject?.name ?? "No project",
            worktreeName: selectedWorktreeName
        ))
    }

    var emptyLabel: String {
        if activeAnnotation?.key == .history, provider == .terminal {
            return "History is unavailable for Terminal"
        }
        if activeAnnotation?.key == .skill, provider == .terminal {
            return "Skills are unavailable for Terminal"
        }
        if activeAnnotation?.key == .history, isHistoryLoading {
            return "Loading history"
        }
        if activeAnnotation != nil {
            return "No matching options"
        }
        return isSlashMode ? "No matching commands" : "No matching sessions"
    }

    var isSlashMode: Bool {
        AskPaletteEntries.slashState(for: fieldText) != nil
    }

    var activeAnnotation: AskActiveAnnotation? {
        parsedInput.activeAnnotation
    }

    var canSend: Bool {
        !isSending && !prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty && selectedProject != nil && selectedWorktree != nil &&
            (sessionMode != .existingSession || selectedSession != nil)
    }

    var selectedProject: Project? {
        guard let projectID else { return nil }
        return projectStore.projects.first { $0.id == projectID }
    }

    var availableWorktrees: [Worktree] {
        guard let projectID else { return [] }
        return worktreeStore.worktrees[projectID] ?? []
    }

    var selectedWorktree: Worktree? {
        guard let worktreeID else { return nil }
        return availableWorktrees.first { $0.id == worktreeID }
    }

    var selectedWorktreeName: String {
        selectedWorktree.map(AskSessionCatalog.displayName(for:)) ?? "No worktree"
    }

    var filteredSessions: [AskSessionOption] {
        guard let projectID, let worktreeID else { return [] }
        return AskSessionCatalog.filter(
            AskSessionCatalog.sessions(projectID: projectID, worktreeID: worktreeID, worktrees: availableWorktrees, appState: appState),
            provider: provider
        )
    }

    var selectedSession: AskSessionOption? {
        filteredSessions.first { $0.id == sessionID }
    }

    var historyOptions: [AskHistoryOption] {
        guard fieldText.contains(AskAnnotationKey.history.token) else { return [] }
        let query = activeAnnotation?.key == .history ? activeAnnotation?.value ?? "" : ""
        guard !query.isEmpty else { return cachedHistoryOptions }
        return cachedHistoryOptions.filter { option in
            option.title.localizedCaseInsensitiveContains(query) ||
                option.sessionID.localizedCaseInsensitiveContains(query)
        }
    }

    var skillOptions: [AskSkillOption] {
        guard provider != .terminal, fieldText.contains(AskAnnotationKey.skill.token) else { return [] }
        return AskSkillCatalog.options(provider: provider, projectPath: selectedProject?.path, query: activeAnnotation?.value ?? "")
    }

    var footerText: String {
        if activeAnnotation != nil {
            return "Enter applies the highlighted option. Esc closes."
        }
        if isSlashMode {
            return "Enter applies the highlighted command. Esc closes."
        }
        if provider == .terminal {
            return "Enter sends. Type / or :p: :wt: :t: :m: to retarget inline. Esc closes."
        }
        return "Enter sends. Type / or :p: :wt: :t: :m: :h: :s: to retarget inline. Esc closes."
    }
}

extension AskOverlay {
    func configureDefaults() {
        projectID = appState.activeProjectID ?? projectStore.projects.first?.id
        syncWorktreeSelection()
        if let activeProject = appState.activeProjectID {
            let activeTab = appState.activeTab(for: activeProject)
            let activePane = activeTab?.content.pane
            let processNames = activePane.flatMap { pane in
                TerminalViewRegistry.shared.foregroundProcessGroupID(for: pane.id)
            }.map { ProcessResourceSampler.samplesForProcessGroup(id: $0).map(\.processName) } ?? []
            provider = AskProvider.detect(
                title: activeTab?.title ?? "",
                startupCommand: activePane?.startupCommand,
                injectedCommand: activePane?.injectedCommand,
                processNames: processNames
            )
        }
        syncSessionSelection()
        fieldText = prompt
        refreshHistoryOptions()
    }

    func handleFieldChange(_ newValue: String) {
        let parsed = AskInlineAnnotations.parse(newValue)
        prompt = parsed.prompt
        applyInlineAnnotations(from: parsed)
        refreshHistoryOptions(parsed: parsed)
        highlightedIndex = entries.isEmpty ? nil : 0
    }

    func refreshHistoryOptions(parsed: AskParsedInput? = nil) {
        let parsed = parsed ?? parsedInput
        guard provider != .terminal, parsed.annotations[.history] != nil || parsed.activeAnnotation?.key == .history else {
            historyLoadTask?.cancel()
            historyLoadTask = nil
            historyCacheKey = nil
            cachedHistoryOptions = []
            isHistoryLoading = false
            return
        }
        let key = AskHistoryCacheKey(provider: provider, projectPath: selectedProject?.path)
        guard historyCacheKey != key else { return }
        historyLoadTask?.cancel()
        historyCacheKey = key
        cachedHistoryOptions = []
        isHistoryLoading = true
        historyLoadTask = Task { @MainActor in
            let options = await Task.detached(priority: .userInitiated) {
                AskHistoryCatalog.options(provider: key.provider, projectPath: key.projectPath, query: "")
            }.value
            guard !Task.isCancelled, historyCacheKey == key else { return }
            isHistoryLoading = false
            cachedHistoryOptions = options
            highlightedIndex = entries.isEmpty ? nil : min(highlightedIndex ?? 0, entries.count - 1)
        }
    }

    func syncWorktreeSelection() {
        guard let projectID else { return }
        let worktrees = worktreeStore.worktrees[projectID] ?? []
        worktreeID = (
            worktrees.first(where: { $0.id == worktreeID })?.id ??
                worktreeStore.preferred(for: projectID, matching: appState.activeWorktreeID[projectID])?.id
        )
            ?? worktrees.first(where: \.isPrimary)?.id
            ?? worktrees.first?.id
        syncSessionSelection()
    }

    func syncSessionSelection() {
        sessionID = filteredSessions.first?.id
        highlightedIndex = entries.isEmpty ? nil : 0
    }

    func applyInlineAnnotations() {
        applyInlineAnnotations(from: AskInlineAnnotations.parse(fieldText))
    }

    func applyInlineAnnotations(from parsed: AskParsedInput) {
        if let projectValue = parsed.annotations[.project],
           let project = projectStore.projects.first(where: { $0.name.compare(
               projectValue,
               options: [.caseInsensitive, .diacriticInsensitive]
           ) == .orderedSame })
        {
            projectID = project.id
        }

        if let providerValue = parsed.annotations[.provider],
           let resolved = AskProvider.resolveAnnotation(providerValue)
        {
            provider = resolved
        }

        if let sessionValue = parsed.annotations[.mode],
           let resolved = AskSessionMode.resolveAnnotation(sessionValue)
        {
            sessionMode = resolved
        }

        if let worktreeValue = parsed.annotations[.worktree],
           let worktree = availableWorktrees.first(where: {
               AskSessionCatalog.displayName(for: $0)
                   .compare(worktreeValue, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
           })
        {
            worktreeID = worktree.id
        }
    }
}
