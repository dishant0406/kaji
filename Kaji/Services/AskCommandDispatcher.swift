import Foundation

@MainActor
enum AskCommandDispatcher {
    static func send(_ request: AskDispatchRequest, appState: AppState) async {
        let prompt = adaptedPrompt(for: request)

        if let history = request.history {
            await sendToHistory(
                history,
                prompt: prompt,
                request: request,
                appState: appState
            )
            return
        }

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
            await sendToExistingSession(session, prompt: prompt, appState: appState)
        case .bestMatch:
            if let match = AskSessionCatalog.bestMatch(in: sessions, provider: request.provider) {
                await sendToExistingSession(match, prompt: prompt, appState: appState)
                return
            }
            await sendToNewSession(
                prompt: prompt,
                project: request.project,
                provider: request.provider,
                appState: appState
            )
        case .newTerminal:
            await sendToNewSession(
                prompt: prompt,
                project: request.project,
                provider: request.provider,
                appState: appState
            )
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
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        _ = await TerminalCommandInjector.submit(prompt, into: session.paneID)
    }

    private static func sendToHistory(
        _ history: AskHistoryOption,
        prompt: String,
        request: AskDispatchRequest,
        appState: AppState
    ) async {
        let resume = resumeCommand(
            for: request.provider,
            sessionID: history.sessionID,
            prompt: prompt
        )
        guard !resume.isEmpty else { return }
        appState.selectProject(request.project, worktree: request.worktree)
        appState.createStartupCommandTab(
            projectID: request.project.id,
            title: request.provider.title,
            command: " ",
            seed: CodingAgentSessionSeed(
                providerID: request.provider.rawValue,
                sessionID: history.sessionID,
                title: history.title,
                transcriptPath: nil,
                cwd: history.projectPath
            ),
            injectedCommand: commandWithCompletionNotification(resume, provider: request.provider)
        )
    }

    private static func sendToNewSession(
        prompt: String,
        project: Project,
        provider: AskProvider,
        appState: AppState
    ) async {
        if provider == .terminal {
            if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                appState.createTab(projectID: project.id)
            } else {
                appState.createCommandTab(projectID: project.id, title: provider.title, command: prompt)
            }
            return
        }

        let previousTabIDs = Set(appState.workspaceTabs(for: project.id).map(\.id))
        let command = commandWithCompletionNotification(
            startupCommand(for: provider, prompt: prompt),
            provider: provider
        )
        guard !command.isEmpty else { return }
        appState.createStartupCommandTab(projectID: project.id, title: provider.title, command: command)
        if let createdTab = appState.workspaceTabs(for: project.id).first(where: { !previousTabIDs.contains($0.id) }) {
            appState.activateWorkspaceTab(createdTab.id, projectID: project.id)
        }
    }

    static func commandWithCompletionNotification(_ command: String, provider: AskProvider) -> String {
        guard provider != .terminal else { return command }
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return command }
        return [
            "{",
            command,
            "; kaji_status=$?; if [ -n \"${KAJI_HOOK_CLIENT_PATH:-}\" ]; then \"$KAJI_HOOK_CLIENT_PATH\" ask-complete",
            ShellEscaper.escape(provider.rawValue),
            ShellEscaper.escape(provider.title),
            "'Session completed'; fi",
            "; exec \"${SHELL:-/bin/zsh}\" -i; }",
        ].joined(separator: " ")
    }

    private static func launchCommand(
        for provider: AskProvider,
        launcherSettings: CLILauncherSettings,
        resolveCommand: (String) -> String
    ) -> String {
        if let launcherID = provider.launcherID {
            let saved = launcherSettings.command(for: launcherID)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !saved.isEmpty {
                return resolveCommand(saved)
            }
        }
        return resolveCommand(provider.definition?.defaultCommand ?? provider.rawValue)
    }

    static func startupCommand(
        for provider: AskProvider,
        prompt: String,
        model: String? = nil,
        resolveCommand: (String) -> String = { CLILauncherCommandResolver.resolve($0) },
        launcherSettings: CLILauncherSettings = .shared
    ) -> String {
        if provider == .terminal {
            return prompt
        }
        guard let agent = CodingAgentRegistry.shared.agent(id: provider.rawValue) else { return "" }
        let base = launchCommand(for: provider, launcherSettings: launcherSettings, resolveCommand: resolveCommand)
        guard !base.isEmpty else { return "" }
        return agent.startupCommand(baseCommand: base, prompt: prompt, model: model)
    }

    static func resumeCommand(
        for provider: AskProvider,
        history: AskHistoryOption,
        prompt: String,
        resolveCommand: (String) -> String = { CLILauncherCommandResolver.resolve($0) },
        launcherSettings: CLILauncherSettings = .shared
    ) -> String {
        resumeCommand(
            for: provider,
            sessionID: history.sessionID,
            prompt: prompt,
            resolveCommand: resolveCommand,
            launcherSettings: launcherSettings
        )
    }

    static func resumeCommand(
        for provider: AskProvider,
        sessionID: String,
        prompt: String,
        resolveCommand: (String) -> String = { CLILauncherCommandResolver.resolve($0) },
        launcherSettings: CLILauncherSettings = .shared
    ) -> String {
        if provider == .terminal {
            return prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let agent = CodingAgentRegistry.shared.agent(id: provider.rawValue) else { return "" }
        let base = launchCommand(for: provider, launcherSettings: launcherSettings, resolveCommand: resolveCommand)
        guard !base.isEmpty else { return "" }
        return agent.resumeCommand(baseCommand: base, sessionID: sessionID, prompt: prompt)
    }

    static func adaptedPrompt(for request: AskDispatchRequest) -> String {
        let prompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let skill = request.skill else { return prompt }

        return CodingAgentRegistry.shared.agent(id: request.provider.rawValue)?.skillPrompt(skill: skill, prompt: prompt) ?? prompt
    }
}
