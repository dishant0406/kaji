import SwiftUI

extension AskOverlay {
    func moveHighlight(_ delta: Int) {
        guard !entries.isEmpty else { return }
        guard let highlightedIndex else {
            self.highlightedIndex = delta > 0 ? 0 : entries.count - 1
            return
        }
        self.highlightedIndex = max(0, min(entries.count - 1, highlightedIndex + delta))
    }

    func handleSubmit() {
        if isSlashMode {
            confirmHighlight()
            return
        }
        if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            confirmHighlight()
            return
        }
        if sessionMode == .existingSession {
            confirmHighlight()
        }
        submit()
    }

    func confirmHighlight() {
        guard let highlightedIndex, highlightedIndex < entries.count else { return }
        apply(entries[highlightedIndex])
    }

    func apply(_ entry: AskPaletteEntry) {
        switch entry.action {
        case .command(let command):
            fieldText = "\(command.trigger) "
        case .project(let project):
            projectID = project.id
            exitSlashMode()
        case .worktree(let worktree):
            worktreeID = worktree.id
            exitSlashMode()
        case .provider(let provider):
            self.provider = provider
            exitSlashMode()
        case .sessionMode(let mode):
            sessionMode = mode
            exitSlashMode()
        case .session(let session):
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
        guard canSend, let selectedProject, let selectedWorktree else { return }
        isSending = true
        Task { @MainActor in
            await AskCommandDispatcher.send(
                prompt: prompt,
                project: selectedProject,
                worktree: selectedWorktree,
                provider: provider,
                sessionMode: sessionMode,
                session: selectedSession,
                appState: appState
            )
            isSending = false
            onDismiss()
        }
    }
}
