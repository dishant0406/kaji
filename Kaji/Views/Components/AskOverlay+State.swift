import SwiftUI

extension AskOverlay {
    var parsedInput: AskParsedInput {
        AskInlineAnnotations.parse(fieldText)
    }

    var entries: [AskPaletteEntry] {
        if isBookmarkFolderPickerVisible {
            return bookmarkFolderEntries
        }
        return AskPaletteEntries.build(.init(
            fieldText: fieldText,
            prompt: prompt,
            projects: projectStore.projects,
            worktrees: availableWorktrees,
            provider: provider,
            sessionMode: sessionMode,
            sessions: filteredSessions,
            bookmarkCandidates: bookmarkCandidates,
            selectedBookmarkIDs: selectedBookmarkIDs,
            bookmarkLookupIsLoading: isBookmarkLookupLoading,
            historyOptions: historyOptions,
            skillOptions: skillOptions,
            taskRecipes: taskRecipeStore.recipes(for: projectID),
            scripts: scriptStore.visibleScripts(projectID: projectID),
            bookmarks: bookmarkStore.bookmarks,
            bookmarkFolders: bookmarkStore.folderNames,
            mentionOptions: mentionOptions,
            directoryOptions: directoryOptions,
            projectName: selectedProject?.name ?? "No project",
            worktreeName: selectedWorktreeName,
            sleepPreventionIsEnabled: SleepPreventionController.shared.isEnabled,
            systemSleepAssertionStatus: SleepPreventionController.shared.systemSleepAssertionStatus,
            batteryLidCloseSleepIsEnabled: SleepPreventionController.shared.isBatteryLidCloseEnabled,
            batteryLidCloseSleepStatus: SleepPreventionController.shared.batteryLidCloseSleepStatus
        ))
    }

    var emptyLabel: String {
        if isBookmarkFolderPickerVisible {
            return "Type a folder name"
        }
        if activeAnnotation?.key == .history, provider == .terminal {
            return "History is unavailable for Terminal"
        }
        if activeAnnotation?.key == .skill, provider == .terminal {
            return "Skills are unavailable for Terminal"
        }
        if activeAnnotation?.key == .history, isHistoryLoading {
            return "Loading history"
        }
        if activeAnnotation?.key == .bookmark {
            return "No matching bookmarks"
        }
        if activeAnnotation?.key == .bookmarkFolder {
            return "No matching bookmark folders"
        }
        if activeAnnotation != nil {
            return "No matching options"
        }
        if AskMentionParser.activeMention(in: fieldText) != nil {
            return "No matching files or folders"
        }
        if isBookmarkSlashMode {
            return isBookmarkLookupLoading ? "Looking for agent sessions" : "No bookmarkable agent sessions"
        }
        return isSlashMode ? "No matching commands" : "No matching sessions"
    }

    var bookmarkCandidates: [AgentSessionBookmarkCandidate] {
        guard isBookmarkSlashMode else { return [] }
        let live = AgentSessionBookmarkCatalog.candidates(appState: appState, worktreeStore: worktreeStore)
        let liveIDs = Set(live.map(\.id))
        return live + fallbackBookmarkCandidates.filter { !liveIDs.contains($0.id) }
    }

    var bookmarkFolderEntries: [AskPaletteEntry] {
        let query = fieldText.trimmingCharacters(in: .whitespacesAndNewlines)
        let folders = bookmarkStore.folderNames.filter { folder in
            query.isEmpty || folder.localizedCaseInsensitiveContains(query)
        }.map { folder in
            AskPaletteEntry(
                action: .bookmarkFolder(folder),
                title: folder,
                detail: "Save selected sessions here",
                annotation: "Enter"
            )
        }
        guard !query.isEmpty,
              !bookmarkStore.folderNames.contains(where: {
                  $0.compare(query, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
              })
        else { return folders }
        let createEntry = AskPaletteEntry(
            action: .createBookmarkFolder(query),
            title: "Create \"\(query)\"",
            detail: "Create folder and save selected sessions",
            annotation: "Shift Enter"
        )
        return [createEntry] + folders
    }

    var slashState: AskSlashState? {
        AskPaletteEntries.slashState(for: fieldText)
    }

    var isBookmarkSlashMode: Bool {
        slashState?.command == .bookmark
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
            if activeAnnotation?.key == .execute {
                return "Enter runs the highlighted script. Esc closes."
            }
            return "Enter applies the highlighted option. Esc closes."
        }
        if AskMentionParser.activeMention(in: fieldText) != nil {
            return "Enter inserts file or folder. Type @ to attach context. Esc closes."
        }
        if isSlashMode {
            if isBookmarkSlashMode {
                return "Enter selects sessions. Shift Enter chooses a bookmark folder. Esc closes."
            }
            return "Enter applies. Shift Enter adds project for /add-project. Esc closes."
        }
        if isBookmarkFolderPickerVisible {
            return "Enter chooses an existing folder. Shift Enter creates/uses the typed folder. Esc closes."
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
        refreshMentionOptions()
        refreshDirectoryOptions()
        guard !isBookmarkFolderPickerVisible else {
            highlightedIndex = entries.isEmpty ? nil : 0
            return
        }
        if !isBookmarkSlashMode {
            selectedBookmarkIDs = []
            fallbackBookmarkCandidates = []
            isBookmarkLookupLoading = false
            fallbackBookmarkTask?.cancel()
            fallbackBookmarkTask = nil
            pendingBookmarkCandidates = []
        } else {
            refreshFallbackBookmarkCandidates()
        }
        highlightedIndex = entries.isEmpty ? nil : 0
    }

    func refreshFallbackBookmarkCandidates() {
        fallbackBookmarkTask?.cancel()
        isBookmarkLookupLoading = true
        fallbackBookmarkTask = Task { @MainActor in
            let candidates = await AgentSessionBookmarkCatalog.fallbackCandidates(
                appState: appState,
                worktreeStore: worktreeStore
            )
            guard !Task.isCancelled else { return }
            fallbackBookmarkCandidates = candidates
            isBookmarkLookupLoading = false
            highlightedIndex = entries.isEmpty ? nil : min(highlightedIndex ?? 0, entries.count - 1)
        }
    }

    func refreshMentionOptions() {
        guard let mention = AskMentionParser.activeMention(in: fieldText), let path = selectedWorktree?.path else {
            mentionLoadTask?.cancel()
            mentionOptions = []
            return
        }
        mentionLoadTask?.cancel()
        mentionLoadTask = Task { @MainActor in
            let options = await AskMentionSearchService.options(query: mention.query, projectPath: path)
            guard !Task.isCancelled else { return }
            mentionOptions = options
        }
    }

    func refreshDirectoryOptions() {
        let parsed = AskInlineAnnotations.parse(fieldText)
        guard parsed.activeAnnotation?.key == .projectAdd else {
            directoryOptions = []
            return
        }
        directoryOptions = AskDirectorySearchService.options(query: parsed.activeAnnotation?.value ?? "~")
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
        let key = AskHistoryCacheKey(provider: provider, projectPath: selectedWorktree?.path ?? selectedProject?.path)
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
