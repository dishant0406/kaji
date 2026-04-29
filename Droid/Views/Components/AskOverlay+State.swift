import SwiftUI

extension AskOverlay {
    var entries: [AskPaletteEntry] {
        AskPaletteEntries.build(
            fieldText: fieldText,
            prompt: prompt,
            projects: projectStore.projects,
            worktrees: availableWorktrees,
            provider: provider,
            sessionMode: sessionMode,
            sessions: filteredSessions,
            projectName: selectedProject?.name ?? "No project",
            worktreeName: selectedWorktreeName
        )
    }

    var emptyLabel: String {
        isSlashMode ? "No matching commands" : "No matching sessions"
    }

    var isSlashMode: Bool {
        AskPaletteEntries.slashState(for: fieldText) != nil
    }

    var canSend: Bool {
        !isSending && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedProject != nil && selectedWorktree != nil &&
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

    var footerText: String {
        isSlashMode ? "Enter applies the highlighted command. Esc closes." : "Enter sends. Type / to switch project, worktree, provider, or session. Esc closes."
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
    }

    func handleFieldChange(_ newValue: String) {
        if !isSlashMode {
            prompt = newValue
        }
        highlightedIndex = entries.isEmpty ? nil : 0
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
}
