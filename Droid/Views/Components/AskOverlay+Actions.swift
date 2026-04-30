import SwiftUI

extension AskOverlay {
    struct AskResolvedTarget {
        let prompt: String
        let project: Project?
        let worktree: Worktree?
        let provider: AskProvider
        let sessionMode: AskSessionMode
        let session: AskSessionOption?
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
        let parsed = AskInlineAnnotations.parse(latestFieldText)
        fieldText = latestFieldText
        prompt = parsed.prompt
        applyInlineAnnotations(from: parsed)

        if parsed.activeAnnotation != nil {
            let updatedFieldText = resolvedFieldTextAfterActiveAnnotationSubmit(
                latestFieldText: latestFieldText,
                parsed: parsed
            )
            fieldText = updatedFieldText
            let reparsed = AskInlineAnnotations.parse(updatedFieldText)
            let target = resolvedTarget(for: reparsed)
            applyResolvedTarget(target)
            let canSendAfterApply = canSend(target: target)
            if AskSubmitPolicy.shouldSendAfterAnnotationApply(
                updatedFieldText: updatedFieldText,
                canSend: canSendAfterApply,
                hasActiveAnnotation: reparsed.activeAnnotation != nil
            ) {
                submit(target: target)
            }
            return
        }
        if isSlashMode {
            confirmHighlight()
            return
        }
        let target = resolvedTarget(for: parsed)
        applyResolvedTarget(target)
        if target.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            confirmHighlight()
            return
        }
        if target.sessionMode == .existingSession {
            confirmHighlight()
        }
        submit(target: target)
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
        case .submit:
            submit()
        }
    }

    func exitSlashMode() {
        fieldText = prompt
        highlightedIndex = entries.isEmpty ? nil : 0
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
            prompt: target.prompt,
            project: selectedProject,
            worktree: selectedWorktree,
            provider: target.provider,
            sessionMode: target.sessionMode,
            session: target.session
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
            projectName: selectedProject?.name ?? "No project",
            worktreeName: selectedWorktreeName
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
            return active.key == .project ? project.name : nil
        case let .worktree(worktree):
            return active.key == .worktree ? AskSessionCatalog.displayName(for: worktree) : nil
        case let .provider(provider):
            return active.key == .provider ? provider.annotationValue : nil
        case let .sessionMode(mode):
            return active.key == .session ? mode.annotationValue : nil
        case .command,
             .session,
             .submit:
            return nil
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
        case .session:
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
        }
    }

    func resolvedTarget(for parsed: AskParsedInput) -> AskResolvedTarget {
        let resolvedProvider = parsed.annotations[.provider].flatMap(AskProvider.resolveAnnotation) ?? provider
        let resolvedSessionMode = parsed.annotations[.session].flatMap(AskSessionMode.resolveAnnotation) ?? sessionMode
        let resolvedProject = parsed.annotations[.project]
            .flatMap(resolveProject(named:))
            ?? selectedProject
        let worktrees = resolvedProject.map { worktreeStore.worktrees[$0.id] ?? [] } ?? []
        let resolvedWorktree = parsed.annotations[.worktree]
            .flatMap { resolveWorktree(named: $0, in: worktrees) }
            ?? preferredWorktree(in: worktrees)
        let sessions: [AskSessionOption]
        if let project = resolvedProject, let worktree = resolvedWorktree {
            sessions = AskSessionCatalog.filter(
                AskSessionCatalog.sessions(
                    projectID: project.id,
                    worktreeID: worktree.id,
                    worktrees: worktrees,
                    appState: appState
                ),
                provider: resolvedProvider
            )
        } else {
            sessions = []
        }
        let resolvedSession = resolvedSessionMode == .existingSession
            ? sessions.first(where: { $0.id == sessionID }) ?? sessions.first
            : nil
        return AskResolvedTarget(
            prompt: parsed.prompt,
            project: resolvedProject,
            worktree: resolvedWorktree,
            provider: resolvedProvider,
            sessionMode: resolvedSessionMode,
            session: resolvedSession
        )
    }

    func canSend(target: AskResolvedTarget) -> Bool {
        !isSending &&
            !target.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            target.project != nil &&
            target.worktree != nil &&
            (target.sessionMode != .existingSession || target.session != nil)
    }

    func applyResolvedTarget(_ target: AskResolvedTarget) {
        prompt = target.prompt
        provider = target.provider
        sessionMode = target.sessionMode
        projectID = target.project?.id
        worktreeID = target.worktree?.id
        sessionID = target.session?.id
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
