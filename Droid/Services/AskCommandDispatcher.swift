import Foundation

@MainActor
enum AskCommandDispatcher {
    static func send(_ request: AskDispatchRequest, appState: AppState) async {
        let trimmed = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        appState.selectProject(request.project, worktree: request.worktree)
        let sessions = AskSessionCatalog.sessions(
            projectID: request.project.id,
            worktreeID: request.worktree.id,
            worktrees: [request.worktree],
            appState: appState
        )

        switch request.sessionMode {
        case .existingSession:
            guard let session = request.session else { return }
            await sendToExistingSession(session, prompt: trimmed, appState: appState)
        case .bestMatch:
            if let match = AskSessionCatalog.bestMatch(in: sessions, provider: request.provider) {
                await sendToExistingSession(match, prompt: trimmed, appState: appState)
                return
            }
            await sendToNewSession(prompt: trimmed, project: request.project, provider: request.provider, appState: appState)
        case .newTerminal:
            await sendToNewSession(prompt: trimmed, project: request.project, provider: request.provider, appState: appState)
        }
    }

    private static func sendToExistingSession(
        _ session: AskSessionOption,
        prompt: String,
        appState: AppState
    ) async {
        appState.dispatch(.navigate(
            projectID: session.projectID,
            worktreeID: session.worktreeID,
            areaID: session.areaID,
            tabID: session.tabID
        ))
        await inject(prompt: prompt, into: session.paneID)
    }

    private static func sendToNewSession(
        prompt: String,
        project: Project,
        provider: AskProvider,
        appState: AppState
    ) async {
        if provider == .terminal {
            appState.createCommandTab(projectID: project.id, title: provider.title, command: prompt)
            return
        }

        let command = startupCommand(for: provider, prompt: prompt)
        guard !command.isEmpty else { return }
        appState.createStartupCommandTab(projectID: project.id, title: provider.title, command: command)
    }

    private static func launchCommand(for provider: AskProvider) -> String {
        if let launcherID = provider.launcherID {
            let saved = CLILauncherSettings.shared.command(for: launcherID)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !saved.isEmpty {
                return saved
            }
        }
        return provider.rawValue
    }

    static func startupCommand(for provider: AskProvider, prompt: String) -> String {
        let base = launchCommand(for: provider)
        guard !base.isEmpty else { return "" }
        let escapedPrompt = ShellEscaper.escape(prompt)

        switch provider {
        case .terminal:
            return prompt
        case .codex,
             .claude:
            return "\(base) \(escapedPrompt)"
        case .opencode:
            return "\(base) --prompt \(escapedPrompt)"
        }
    }

    private static func inject(prompt: String, into paneID: UUID) async {
        for _ in 0 ..< 80 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard let view = TerminalViewRegistry.shared.view(for: paneID), view.hasLiveSurface else { continue }
            view.sendText(prompt)
            view.sendReturnKey()
            return
        }
    }
}
