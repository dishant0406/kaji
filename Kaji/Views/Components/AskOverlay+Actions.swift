import SwiftUI

extension AskOverlay {
    struct AskResolvedTarget {
        let prompt: String
        let project: Project?
        let worktree: Worktree?
        let provider: AskProvider
        let sessionMode: AskSessionMode
        let session: AskSessionOption?
        let history: AskHistoryOption?
        let skill: AskSkillOption?
        let task: AskTaskRecipe?
        let hasInvalidProviderOption: Bool
    }

    func moveHighlight(_ delta: Int) {
        guard !entries.isEmpty else { return }
        guard let highlightedIndex else {
            self.highlightedIndex = delta > 0 ? 0 : entries.count - 1
            return
        }
        self.highlightedIndex = max(0, min(entries.count - 1, highlightedIndex + delta))
    }

    func handleSubmit() {
        handleSubmit(fieldText)
    }

    func handleSubmit(_ latestFieldText: String) {
        if isBookmarkFolderPickerVisible {
            confirmHighlight()
            return
        }
        if isTaskFormVisible {
            saveTaskForm()
            return
        }
        if isScriptFormVisible {
            saveScriptForm()
            return
        }
        if pendingRiskyScript != nil {
            confirmPendingScript()
            return
        }
        if pendingGitCommand != nil {
            confirmPendingGitCommand()
            return
        }
        if GitCommandParser.state(for: latestFieldText) != nil {
            confirmHighlight()
            return
        }
        let parsed = AskInlineAnnotations.parse(latestFieldText)
        fieldText = latestFieldText
        prompt = parsed.prompt
        applyInlineAnnotations(from: parsed)

        if handleResolvedScriptAnnotation(parsed) { return }

        if AskMentionParser.activeMention(in: latestFieldText) != nil {
            confirmHighlight()
            return
        }

        if let activeAnnotation = parsed.activeAnnotation {
            if handleUtilityAnnotation(activeAnnotation) { return }
            if AskSubmitPolicy.shouldApplyHighlightedEntry(key: activeAnnotation.key) {
                confirmHighlight()
                return
            }
            let activeTarget = resolvedTarget(for: parsed)
            if activeAnnotationIsResolved(activeAnnotation, target: activeTarget) {
                applyResolvedTarget(activeTarget)
                submit(target: activeTarget)
                return
            }
            let updatedFieldText = resolvedFieldTextAfterActiveAnnotationSubmit(
                latestFieldText: latestFieldText,
                parsed: parsed
            )
            fieldText = updatedFieldText
            let reparsed = AskInlineAnnotations.parse(updatedFieldText)
            let target = resolvedTarget(for: reparsed)
            applyResolvedTarget(target)
            let canSendAfterApply = canSend(target: target)
            let needsResolution = activeAnnotationNeedsResolution(reparsed.activeAnnotation, target: target)
            if AskSubmitPolicy.shouldSendAfterAnnotationApply(
                appliedKey: activeAnnotation.key,
                updatedFieldText: updatedFieldText,
                canSend: canSendAfterApply,
                hasActiveAnnotation: needsResolution
            ) {
                submit(target: target)
            }
            return
        }
        if isSlashMode {
            if handleBookmarkSubmit() { return }
            confirmHighlight()
            return
        }
        let target = resolvedTarget(for: parsed)
        applyResolvedTarget(target)
        if targetHasMissingSelection(target, parsed: parsed) {
            confirmHighlight()
            return
        }
        if target.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if parsed.annotations.isEmpty {
                confirmHighlight()
                return
            }
        }
        if target.sessionMode == .existingSession {
            confirmHighlight()
        }
        submit(target: target)
    }

    func handleShiftSubmit(_ latestFieldText: String) {
        if isBookmarkFolderPickerVisible {
            savePendingBookmarks(folderName: latestFieldText)
            return
        }
        let parsed = AskInlineAnnotations.parse(latestFieldText)
        guard parsed.activeAnnotation?.key == .projectAdd else {
            if handleBookmarkShiftSubmit() { return }
            handleSubmit(latestFieldText)
            return
        }
        if let highlightedIndex, highlightedIndex < entries.count, case let .directory(directory) = entries[highlightedIndex].action {
            addProject(directory.path)
            return
        }
        addProject(AskDirectorySearchService.expandHome(parsed.activeAnnotation?.value ?? "~"))
    }

    func handleUtilityAnnotation(_ annotation: AskActiveAnnotation) -> Bool {
        switch annotation.key {
        case .taskAdd:
            openTaskForm()
        case .attach:
            attachments.append(contentsOf: AskAttachmentLoader.openPanel())
        case .executeAdd:
            openScriptForm()
        case .execute,
             .executeEdit,
             .executeDelete:
            confirmHighlight()
        case .taskEdit,
             .taskDelete,
             .projectAdd,
             .diff:
            confirmHighlight()
        case .project,
             .worktree,
             .provider,
             .mode,
             .history,
             .skill,
             .task,
             .bookmark,
             .bookmarkFolder:
            return false
        }
        return true
    }

    func handleResolvedScriptAnnotation(_ parsed: AskParsedInput) -> Bool {
        if let slug = parsed.annotations[.execute], let script = scriptStore.resolve(slug: slug, projectID: projectID) {
            runScript(script)
            return true
        }
        if parsed.annotations[.executeAdd] != nil {
            openScriptForm()
            return true
        }
        if let slug = parsed.annotations[.executeEdit], let script = scriptStore.resolve(slug: slug, projectID: projectID) {
            openScriptForm(script: script)
            return true
        }
        if let slug = parsed.annotations[.executeDelete], let script = scriptStore.resolve(slug: slug, projectID: projectID) {
            scriptStore.delete(script)
            return true
        }
        return false
    }

    func confirmHighlight() {
        guard let highlightedIndex, highlightedIndex < entries.count else { return }
        apply(entries[highlightedIndex])
    }

    func apply(_ entry: AskPaletteEntry) {
        switch entry.action {
        case let .command(command):
            fieldText = "\(command.trigger) "
        case let .project(project):
            applyAnnotationSelection(value: project.name)
        case let .worktree(worktree):
            applyAnnotationSelection(value: AskSessionCatalog.displayName(for: worktree))
        case let .provider(provider):
            applyAnnotationSelection(value: provider.annotationValue)
        case let .sessionMode(mode):
            applyAnnotationSelection(value: mode.annotationValue)
        case let .session(session):
            sessionID = session.id
        case let .bookmarkSession(candidate, selected):
            if selected {
                selectedBookmarkIDs.remove(candidate.id)
            } else {
                selectedBookmarkIDs.insert(candidate.id)
            }
        case .saveSelectedBookmarks:
            beginBookmarkFolderSelection(selectedBookmarkCandidates())
        case .bookmarkLookupLoading:
            return
        case let .bookmarkFolder(folder):
            savePendingBookmarks(folderName: folder)
        case let .createBookmarkFolder(folder):
            savePendingBookmarks(folderName: folder)
        case let .savedBookmark(bookmark):
            resumeBookmark(bookmark)
        case let .bookmarkFolderFilter(folder):
            applyBookmarkFolderFilter(folder)
        case let .history(history):
            applyAnnotationSelection(value: history.sessionID)
        case let .skill(skill):
            applyAnnotationSelection(value: skill.name)
        case let .taskRecipe(recipe):
            fieldText = recipe.prompt
            prompt = recipe.prompt
        case .openTaskForm:
            openTaskForm()
        case let .editTaskRecipe(recipe):
            openTaskForm(recipe: recipe)
        case let .deleteTaskRecipe(recipe):
            taskRecipeStore.delete(id: recipe.id)
            highlightedIndex = entries.isEmpty ? nil : 0
        case let .mention(option):
            applyMention(option)
        case let .directory(directory):
            fieldText = "\(AskAnnotationKey.projectAdd.token)\(directory.path)/"
        case let .diffFile(file):
            openDiffFile(file)
        case let .openDiffSummary(projectID, worktreeID, worktreePath):
            openDiffSummary(projectID: projectID, worktreeID: worktreeID, worktreePath: worktreePath)
        case let .gitCommand(request):
            runGitCommand(request)
        case let .gitBranch(name, _):
            fieldText = "\(GitPaletteCommand.switchBranch.trigger) \(name)"
            highlightedIndex = entries.isEmpty ? nil : 0
        case let .gitSwitchBranch(branch):
            runGitCommand(GitCommandParser.request(command: .switchBranch, input: branch))
        case let .gitCheckoutBranch(branch):
            runGitCommand(GitCommandParser.request(command: .checkout, input: branch))
        case let .gitCommitDiff(commit, projectID, worktreeID, worktreePath):
            appState.openCommitDiffViewer(commit: commit, projectID: projectID, worktreeID: worktreeID, worktreePath: worktreePath)
            onDismiss()
        case .gitPreviewPlaceholder:
            return
        case .attach:
            attachments.append(contentsOf: AskAttachmentLoader.openPanel())
        case let .runScript(script):
            runScript(script)
        case let .openScriptForm(script):
            openScriptForm(script: script)
        case let .deleteScript(script):
            scriptStore.delete(script)
            highlightedIndex = entries.isEmpty ? nil : 0
        case .toggleSleepPrevention:
            SleepPreventionController.shared.toggle()
            onDismiss()
        case .toggleBatteryLidCloseSleepPrevention:
            SleepPreventionController.shared.toggleBatteryLidClose()
            onDismiss()
        case .launchProvider:
            submit()
        case .submit:
            submit()
        }
    }

    func handleSpace() -> Bool {
        guard isBookmarkSlashMode,
              let highlightedIndex,
              highlightedIndex < entries.count,
              case let .bookmarkSession(candidate, selected) = entries[highlightedIndex].action
        else { return false }
        if selected {
            selectedBookmarkIDs.remove(candidate.id)
        } else {
            selectedBookmarkIDs.insert(candidate.id)
        }
        return true
    }

    func handleBookmarkSubmit() -> Bool {
        guard isBookmarkSlashMode else { return false }
        guard !bookmarkCandidates.isEmpty else { return true }
        confirmHighlight()
        return true
    }

    func handleBookmarkShiftSubmit() -> Bool {
        guard isBookmarkSlashMode else { return false }
        let selected = selectedBookmarkCandidates()
        let candidates = selected.isEmpty ? bookmarkCandidates : selected
        guard !candidates.isEmpty else { return true }
        beginBookmarkFolderSelection(candidates)
        return true
    }

    func selectedBookmarkCandidates() -> [AgentSessionBookmarkCandidate] {
        bookmarkCandidates.filter { selectedBookmarkIDs.contains($0.id) }
    }

    func beginBookmarkFolderSelection(_ candidates: [AgentSessionBookmarkCandidate]) {
        guard !candidates.isEmpty else { return }
        pendingBookmarkCandidates = candidates
        isBookmarkFolderPickerVisible = true
        fieldText = ""
        highlightedIndex = entries.isEmpty ? nil : 0
    }

    func savePendingBookmarks(folderName: String) {
        guard !pendingBookmarkCandidates.isEmpty else { return }
        bookmarkStore.save(pendingBookmarkCandidates, folderName: folderName)
        onDismiss()
    }

    func applyBookmarkFolderFilter(_ folder: String) {
        fieldText = "\(AskAnnotationKey.bookmarkFolder.token)\(folder) \(AskAnnotationKey.bookmark.token)"
        prompt = AskInlineAnnotations.parse(fieldText).prompt
        highlightedIndex = entries.isEmpty ? nil : 0
    }

    func resumeBookmark(_ bookmark: AgentSessionBookmark) {
        guard let project = projectStore.projects.first(where: { $0.id == bookmark.projectID }) else { return }
        let worktrees = worktreeStore.worktrees[bookmark.projectID] ?? []
        guard let worktree = worktrees.first(where: { $0.id == bookmark.worktreeID })
            ?? worktrees.first(where: { $0.path == bookmark.worktreePath })
            ?? worktreeStore.primary(for: bookmark.projectID)
        else { return }
        let provider = AskProvider(agentID: bookmark.providerID)
        let command = AskCommandDispatcher.commandWithCompletionNotification(
            AskCommandDispatcher.resumeCommand(for: provider, sessionID: bookmark.sessionID, prompt: ""),
            provider: provider
        )
        guard !command.isEmpty else { return }
        appState.selectProject(project, worktree: worktree)
        appState.createStartupCommandTab(
            projectID: project.id,
            title: provider.title,
            command: " ",
            seed: CodingAgentSessionSeed(
                providerID: provider.rawValue,
                sessionID: bookmark.sessionID,
                title: bookmark.title,
                transcriptPath: nil,
                cwd: bookmark.worktreePath
            ),
            injectedCommand: command
        )
        onDismiss()
    }

    func exitSlashMode() {
        fieldText = prompt
        highlightedIndex = entries.isEmpty ? nil : 0
    }

    func applyPrefillIfNeeded() {
        let prefill = prefillState.consume()
        guard !prefill.isEmpty else { return }
        fieldText = prefill
        prompt = prefill
        handleFieldChange(prefill)
    }

    func submit() {
        submit(target: resolvedTarget(for: AskInlineAnnotations.parse(fieldText)))
    }

    func submit(target: AskResolvedTarget) {
        guard canSend(target: target),
              let selectedProject = target.project,
              let selectedWorktree = target.worktree
        else { return }
        isSending = true
        let request = AskDispatchRequest(
            prompt: promptWithAttachments(target.prompt),
            project: selectedProject,
            worktree: selectedWorktree,
            provider: target.provider,
            sessionMode: target.sessionMode,
            session: target.session,
            history: target.history,
            skill: target.skill
        )
        Task { @MainActor in
            await AskCommandDispatcher.send(request, appState: appState)
            isSending = false
            onDismiss()
        }
    }

    func applyAnnotationSelection(value: String) {
        guard let active = activeAnnotation else {
            exitSlashMode()
            return
        }
        fieldText = AskInlineAnnotations.replacingActiveAnnotation(
            in: fieldText,
            with: "\(active.key.token)\(value)"
        )
        prompt = parsedInput.prompt
        applyInlineAnnotations()
        highlightedIndex = entries.isEmpty ? nil : 0
    }

    func applyMention(_ option: AskMentionOption) {
        guard let mention = AskMentionParser.activeMention(in: fieldText) else { return }
        fieldText = AskMentionParser.replacingActiveMention(in: fieldText, mention: mention, with: option.path)
        prompt = AskInlineAnnotations.parse(fieldText).prompt
        mentionOptions = []
    }

    func openTaskForm() {
        isScriptFormVisible = false
        isTaskFormVisible = true
        editingTaskID = nil
        taskFormName = ""
        taskFormPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        taskFormScope = AskTaskRecipeScope.global.rawValue
    }

    func openTaskForm(recipe: AskTaskRecipe) {
        isTaskFormVisible = true
        editingTaskID = recipe.id
        taskFormName = recipe.name
        taskFormPrompt = recipe.prompt
        taskFormScope = recipe.isGlobal ? AskTaskRecipeScope.global.rawValue : AskTaskRecipeScope.project.rawValue
    }

    func closeTaskForm() {
        isTaskFormVisible = false
        editingTaskID = nil
    }

    func openScriptForm(script: KajiKitScript? = nil) {
        isTaskFormVisible = false
        isScriptFormVisible = true
        scriptDraft = script.map(KajiKitScriptDraft.init(script:)) ?? KajiKitScriptDraft()
        if script == nil {
            scriptDraft.scope = projectID == nil ? .global : .project
        }
    }

    func closeScriptForm() {
        isScriptFormVisible = false
        scriptDraft = KajiKitScriptDraft()
    }

    func saveScriptForm() {
        scriptStore.save(scriptDraft, projectID: projectID)
        closeScriptForm()
        highlightedIndex = entries.isEmpty ? nil : 0
    }

    func runScript(_ script: KajiKitScript) {
        if script.confirmation == .always || script.confirmation == .risky && KajiKitScriptPlanner.isRisky(script) {
            pendingRiskyScript = script
            return
        }
        startScript(script)
    }

    func confirmPendingScript() {
        guard let script = pendingRiskyScript else { return }
        pendingRiskyScript = nil
        startScript(script)
    }

    func cancelPendingScript() {
        pendingRiskyScript = nil
    }

    func startScript(_ script: KajiKitScript) {
        guard let plan = try? KajiKitScriptPlanner.plan(
            script: script,
            project: selectedProject,
            worktree: selectedWorktree
        )
        else { return }
        scriptPlan = plan
        scriptRunner.run(plan)
    }

    func stopScriptRun() {
        scriptRunner.stop()
        finishScriptRun()
    }

    func finishScriptRun() {
        scriptRunner.stop()
        scriptPlan = nil
        onDismiss()
    }

    func saveTaskForm() {
        let scope = AskTaskRecipeScope(rawValue: taskFormScope) ?? .global
        let scopedProjectID = scope == .project ? projectID : nil
        if let editingTaskID {
            taskRecipeStore.update(id: editingTaskID, name: taskFormName, prompt: taskFormPrompt, projectID: scopedProjectID)
        } else {
            taskRecipeStore.save(name: taskFormName, prompt: taskFormPrompt, projectID: scopedProjectID)
        }
        let savedPrompt = taskFormPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        isTaskFormVisible = false
        editingTaskID = nil
        if !savedPrompt.isEmpty {
            fieldText = savedPrompt
            prompt = savedPrompt
        }
    }

    func addProject(_ rawPath: String) {
        let path = AskDirectorySearchService.expandHome(rawPath).trimmingCharacters(in: .whitespacesAndNewlines)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { return }
        if let existing = projectStore.projects.first(where: { $0.path == path }) {
            guard let primary = worktreeStore.primary(for: existing.id) else { return }
            projectID = existing.id
            appState.selectProject(existing, worktree: primary)
            onDismiss()
            return
        }
        let project = Project(name: URL(fileURLWithPath: path).lastPathComponent, path: path, sortOrder: projectStore.projects.count)
        projectStore.add(project)
        worktreeStore.ensurePrimary(for: project)
        guard let primary = worktreeStore.primary(for: project.id) else { return }
        projectID = project.id
        appState.selectProject(project, worktree: primary)
        onDismiss()
    }

    func openDiffFile(_ diffFile: DiffPaletteFile) {
        guard let project = projectStore.projects.first(where: { $0.id == diffFile.projectID }) else { return }
        guard let worktree = worktreeStore.worktree(projectID: diffFile.projectID, worktreeID: diffFile.worktreeID) else { return }
        appState.selectProject(project, worktree: worktree)
        appState.openDiffViewer(
            vcs: VCSTabState(projectPath: diffFile.worktreePath, files: [diffFile.file]),
            filePath: diffFile.file.path,
            isStaged: diffFile.isStaged,
            projectID: diffFile.projectID
        )
        onDismiss()
    }

    func openDiffSummary(projectID: UUID, worktreeID: UUID, worktreePath: String) {
        guard let project = projectStore.projects.first(where: { $0.id == projectID }) else { return }
        guard let worktree = worktreeStore.worktree(projectID: projectID, worktreeID: worktreeID) else { return }
        let files = Dictionary(grouping: diffFiles, by: { $0.file.path })
            .compactMap { $0.value.first?.file }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        guard !files.isEmpty else { return }
        appState.selectProject(project, worktree: worktree)
        appState.openAllChangesDiffViewer(
            vcs: VCSTabState(projectPath: worktreePath, files: files),
            projectID: projectID
        )
        onDismiss()
    }

    func promptWithAttachments(_ base: String) -> String {
        guard !attachments.isEmpty else { return base }
        let paths = attachments.map { "- \($0.url.path)" }.joined(separator: "\n")
        return [base, "Attached images:", paths].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    func resolvedFieldTextAfterActiveAnnotationSubmit(
        latestFieldText: String,
        parsed: AskParsedInput
    ) -> String {
        let localEntries = AskPaletteEntries.build(.init(
            fieldText: latestFieldText,
            prompt: parsed.prompt,
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
            gitBranches: gitBranches,
            currentGitBranch: currentGitBranch,
            isLoadingGitBranches: isLoadingGitBranches,
            projectName: selectedProject?.name ?? "No project",
            worktreeName: selectedWorktreeName,
            sleepPreventionIsEnabled: SleepPreventionController.shared.isEnabled,
            systemSleepAssertionStatus: SleepPreventionController.shared.systemSleepAssertionStatus
        ))

        guard let highlightedIndex, highlightedIndex < localEntries.count,
              let active = parsed.activeAnnotation,
              let replacement = annotationReplacement(for: localEntries[highlightedIndex], active: active)
        else {
            guard let active = parsed.activeAnnotation,
                  let replacement = fallbackAnnotationReplacement(for: active)
            else { return latestFieldText }
            return AskInlineAnnotations.replacingActiveAnnotation(
                in: latestFieldText,
                with: "\(active.key.token)\(replacement)"
            )
        }

        return AskInlineAnnotations.replacingActiveAnnotation(
            in: latestFieldText,
            with: "\(active.key.token)\(replacement)"
        )
    }

    func annotationReplacement(for entry: AskPaletteEntry, active: AskActiveAnnotation) -> String? {
        switch entry.action {
        case let .project(project):
            active.key == .project ? project.name : nil
        case let .worktree(worktree):
            active.key == .worktree ? AskSessionCatalog.displayName(for: worktree) : nil
        case let .provider(provider):
            active.key == .provider ? provider.annotationValue : nil
        case let .sessionMode(mode):
            active.key == .mode ? mode.annotationValue : nil
        case let .history(history):
            active.key == .history ? history.sessionID : nil
        case let .skill(skill):
            active.key == .skill ? skill.name : nil
        case let .taskRecipe(recipe):
            active.key == .task ? recipe.prompt : nil
        case let .bookmarkFolderFilter(folder):
            active.key == .bookmarkFolder ? folder : nil
        case .command,
             .openTaskForm,
             .editTaskRecipe,
             .deleteTaskRecipe,
             .bookmarkSession,
             .bookmarkLookupLoading,
             .saveSelectedBookmarks,
             .bookmarkFolder,
             .createBookmarkFolder,
             .savedBookmark,
             .gitCommand,
             .gitBranch,
             .gitSwitchBranch,
             .gitCheckoutBranch,
             .gitCommitDiff,
             .gitPreviewPlaceholder,
             .runScript,
             .openScriptForm,
             .deleteScript,
             .toggleSleepPrevention,
             .toggleBatteryLidCloseSleepPrevention,
             .mention,
             .directory,
             .diffFile,
             .openDiffSummary,
             .attach,
             .session,
             .launchProvider,
             .submit:
            nil
        }
    }

    func fallbackAnnotationReplacement(for active: AskActiveAnnotation) -> String? {
        switch active.key {
        case .provider:
            let matches = AskProvider.allCases.filter { provider in
                if active.value.isEmpty { return true }
                let normalized = active.value.lowercased()
                return provider.annotationValue.hasPrefix(normalized) ||
                    provider.rawValue.hasPrefix(normalized) ||
                    provider.title.lowercased().hasPrefix(normalized)
            }
            return matches.count == 1 ? matches[0].annotationValue : nil
        case .mode:
            let matches = AskSessionMode.allCases.filter { mode in
                if active.value.isEmpty { return true }
                let normalized = active.value.lowercased()
                return mode.annotationValue.hasPrefix(normalized) ||
                    mode.rawValue.lowercased().hasPrefix(normalized) ||
                    mode.title.lowercased().hasPrefix(normalized)
            }
            return matches.count == 1 ? matches[0].annotationValue : nil
        case .project:
            let matches = projectStore.projects.filter { project in
                if active.value.isEmpty { return true }
                return project.name.localizedCaseInsensitiveContains(active.value)
            }
            return matches.count == 1 ? matches[0].name : nil
        case .worktree:
            let matches = availableWorktrees.filter { worktree in
                let name = AskSessionCatalog.displayName(for: worktree)
                if active.value.isEmpty { return true }
                return name.localizedCaseInsensitiveContains(active.value)
            }
            return matches.count == 1 ? AskSessionCatalog.displayName(for: matches[0]) : nil
        case .history:
            let matches = historyOptions.filter { option in
                if active.value.isEmpty { return true }
                return option.sessionID.localizedCaseInsensitiveContains(active.value) ||
                    option.title.localizedCaseInsensitiveContains(active.value)
            }
            return matches.count == 1 ? matches[0].sessionID : nil
        case .skill:
            let matches = skillOptions.filter { option in
                if active.value.isEmpty { return true }
                return option.name.localizedCaseInsensitiveContains(active.value) ||
                    option.title.localizedCaseInsensitiveContains(active.value)
            }
            return matches.count == 1 ? matches[0].name : nil
        case .task:
            let matches = taskRecipeStore.recipes(for: projectID).filter { option in
                if active.value.isEmpty { return true }
                return option.name.localizedCaseInsensitiveContains(active.value)
            }
            return matches.count == 1 ? matches[0].prompt : nil
        case .taskAdd,
             .taskEdit,
             .taskDelete,
             .projectAdd,
             .diff,
             .attach,
             .execute,
             .executeAdd,
             .executeEdit,
             .executeDelete,
             .bookmark,
             .bookmarkFolder:
            return nil
        }
    }

    func resolvedTarget(for parsed: AskParsedInput) -> AskResolvedTarget {
        let resolvedTask = parsed.annotations[.task].flatMap(resolveTask(named:))
        let resolvedProvider = resolvedProvider(parsed: parsed, task: resolvedTask)
        let resolvedSessionMode = parsed.annotations[.mode].flatMap(AskSessionMode.resolveAnnotation) ?? sessionMode
        let resolvedProject = parsed.annotations[.project]
            .flatMap(resolveProject(named:))
            ?? selectedProject
        let worktrees = resolvedProject.map { worktreeStore.worktrees[$0.id] ?? [] } ?? []
        let resolvedWorktree = parsed.annotations[.worktree]
            .flatMap { resolveWorktree(named: $0, in: worktrees) }
            ?? preferredWorktree(in: worktrees)
        let sessions: [AskSessionOption] = if let project = resolvedProject, let worktree = resolvedWorktree {
            AskSessionCatalog.filter(
                AskSessionCatalog.sessions(
                    projectID: project.id,
                    worktreeID: worktree.id,
                    worktrees: worktrees,
                    appState: appState
                ),
                provider: resolvedProvider
            )
        } else {
            []
        }
        let resolvedSession = resolvedSessionMode == .existingSession
            ? sessions.first(where: { $0.id == sessionID }) ?? sessions.first
            : nil
        let resolvedHistory = parsed.annotations[.history].flatMap { historyID in
            cachedHistoryOptions.first { $0.provider == resolvedProvider && $0.sessionID == historyID }
        }
        let resolvedSkill = parsed.annotations[.skill].flatMap { skillName in
            AskSkillCatalog.options(
                provider: resolvedProvider,
                projectPath: resolvedProject?.path,
                query: skillName
            ).first { $0.name == skillName }
        }
        return AskResolvedTarget(
            prompt: prompt(parsed.prompt, task: resolvedTask),
            project: resolvedProject,
            worktree: resolvedWorktree,
            provider: resolvedProvider,
            sessionMode: resolvedSessionMode,
            session: resolvedSession,
            history: resolvedHistory,
            skill: resolvedSkill,
            task: resolvedTask,
            hasInvalidProviderOption: invalidProviderOption(
                parsed: parsed,
                provider: resolvedProvider,
                history: resolvedHistory,
                skill: resolvedSkill,
                task: resolvedTask
            )
        )
    }

    func resolvedProvider(parsed: AskParsedInput, task: AskTaskRecipe?) -> AskProvider {
        if let annotated = parsed.annotations[.provider].flatMap(AskProvider.resolveAnnotation) {
            return annotated
        }
        if task != nil, provider == .terminal {
            return CLILauncherSettings.shared.enabledLaunchers.first.map { AskProvider(agentID: $0.id) } ?? .terminal
        }
        return provider
    }

    func prompt(_ base: String, task: AskTaskRecipe?) -> String {
        let cleanBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let task else { return cleanBase }
        return [task.prompt, cleanBase].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    func canSend(target: AskResolvedTarget) -> Bool {
        !isSending &&
            !target.hasInvalidProviderOption &&
            target.project != nil &&
            target.worktree != nil &&
            (target.history != nil || target.sessionMode != .existingSession || target.session != nil)
    }

    func targetHasMissingSelection(_ target: AskResolvedTarget, parsed: AskParsedInput) -> Bool {
        if target.hasInvalidProviderOption { return true }
        return (parsed.annotations[.history] != nil && target.history == nil) ||
            (parsed.annotations[.skill] != nil && target.skill == nil) ||
            (parsed.annotations[.task] != nil && target.task == nil)
    }

    func invalidProviderOption(
        parsed: AskParsedInput,
        provider: AskProvider,
        history: AskHistoryOption?,
        skill: AskSkillOption?,
        task: AskTaskRecipe?
    ) -> Bool {
        if provider == .terminal {
            return parsed.annotations[.history] != nil || parsed.annotations[.skill] != nil || parsed.annotations[.task] != nil
        }
        return (parsed.annotations[.history] != nil && history == nil) ||
            (parsed.annotations[.skill] != nil && skill == nil) ||
            (parsed.annotations[.task] != nil && task == nil)
    }

    func activeAnnotationNeedsResolution(_ active: AskActiveAnnotation?, target: AskResolvedTarget) -> Bool {
        guard let active else { return false }
        switch active.key {
        case .history:
            return target.history == nil
        case .skill:
            return target.skill == nil
        case .task:
            return target.task == nil
        case .taskAdd,
             .taskEdit,
             .taskDelete,
             .projectAdd,
             .diff,
             .attach,
             .execute,
             .executeAdd,
             .executeEdit,
             .executeDelete,
             .bookmark,
             .bookmarkFolder:
            return false
        case .provider,
             .mode,
             .project,
             .worktree:
            return true
        }
    }

    func activeAnnotationIsResolved(_ active: AskActiveAnnotation, target: AskResolvedTarget) -> Bool {
        AskSubmitPolicy.activeAnnotationIsResolved(
            key: active.key,
            hasHistory: target.history != nil,
            hasSkill: target.skill != nil
        )
    }

    func applyResolvedTarget(_ target: AskResolvedTarget) {
        prompt = target.prompt
        provider = target.provider
        sessionMode = target.sessionMode
        projectID = target.project?.id
        worktreeID = target.worktree?.id
        sessionID = target.session?.id
    }

    func resolveTask(named name: String) -> AskTaskRecipe? {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let scopedRecipes = taskRecipeStore.recipes(for: projectID)
        return scopedRecipes.first {
            $0.name.compare(normalized, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        } ?? scopedRecipes.first {
            $0.name.localizedCaseInsensitiveContains(normalized) || $0.id.localizedCaseInsensitiveContains(normalized)
        }
    }

    func resolveProject(named name: String) -> Project? {
        projectStore.projects.first {
            $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    func resolveWorktree(named name: String, in worktrees: [Worktree]) -> Worktree? {
        worktrees.first {
            AskSessionCatalog.displayName(for: $0)
                .compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    func preferredWorktree(in worktrees: [Worktree]) -> Worktree? {
        if let worktreeID {
            return worktrees.first(where: { $0.id == worktreeID })
        }
        return worktrees.first(where: \.isPrimary) ?? worktrees.first
    }
}
