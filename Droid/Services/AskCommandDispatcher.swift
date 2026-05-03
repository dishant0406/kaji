import Foundation

@MainActor
enum AskCommandDispatcher {
    static func send(_ request: AskDispatchRequest, appState: AppState) async {
        let prompt = adaptedPrompt(for: request)

        appState.selectProject(request.project, worktree: request.worktree)
        let sessions = AskSessionCatalog.sessions(
            projectID: request.project.id,
            worktreeID: request.worktree.id,
            worktrees: [request.worktree],
            appState: appState
        )

        if let history = request.history {
            await sendToHistory(history, prompt: prompt, project: request.project, provider: request.provider, appState: appState)
            return
        }

        switch request.sessionMode {
        case .existingSession:
            guard let session = request.session else { return }
            await sendToExistingSession(session, prompt: prompt, appState: appState)
        case .bestMatch:
            if let match = AskSessionCatalog.bestMatch(in: sessions, provider: request.provider) {
                await sendToExistingSession(match, prompt: prompt, appState: appState)
                return
            }
            await sendToNewSession(prompt: prompt, project: request.project, provider: request.provider, appState: appState)
        case .newTerminal:
            await sendToNewSession(prompt: prompt, project: request.project, provider: request.provider, appState: appState)
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
        project: Project,
        provider: AskProvider,
        appState: AppState
    ) async {
        let command = commandWithCompletionNotification(
            resumeCommand(for: provider, history: history, prompt: prompt),
            provider: provider
        )
        guard !command.isEmpty else { return }
        appState.createStartupCommandTab(projectID: project.id, title: provider.title, command: command)
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

        let command = commandWithCompletionNotification(startupCommand(for: provider, prompt: prompt), provider: provider)
        guard !command.isEmpty else { return }
        appState.createStartupCommandTab(projectID: project.id, title: provider.title, command: command)
    }

    static func commandWithCompletionNotification(_ command: String, provider: AskProvider) -> String {
        guard provider != .terminal else { return command }
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return command }
        return [
            "{",
            command,
            "; droid_status=$?; if [ -n \"${DROID_HOOK_CLIENT_PATH:-}\" ]; then \"$DROID_HOOK_CLIENT_PATH\" ask-complete",
            ShellEscaper.escape(provider.rawValue),
            ShellEscaper.escape(provider.title),
            "'Session completed'; fi",
            "; exec \"${SHELL:-/bin/zsh}\" -i; }",
        ].joined(separator: " ")
    }

    private static func launchCommand(for provider: AskProvider) -> String {
        if let launcherID = provider.launcherID {
            let saved = CLILauncherSettings.shared.command(for: launcherID)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !saved.isEmpty {
                return resolvedCommand(saved)
            }
        }
        return resolvedCommand(provider.rawValue)
    }

    private static func resolvedCommand(_ command: String) -> String {
        let parts = command.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = parts.first else { return command }
        let executable = String(first)
        guard !executable.contains("/") else { return command }
        guard let resolved = AIProviderExecutableLocator.resolvePath(for: executable) else { return command }
        guard parts.count == 2 else { return ShellEscaper.escape(resolved) }
        return "\(ShellEscaper.escape(resolved)) \(parts[1])"
    }

    static func startupCommand(for provider: AskProvider, prompt: String, model: String? = nil) -> String {
        let base = launchCommand(for: provider)
        guard !base.isEmpty else { return "" }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelArguments = modelArguments(for: provider, model: model)
        guard !trimmed.isEmpty else { return ([base] + modelArguments).joined(separator: " ") }
        let escapedPrompt = ShellEscaper.escape(trimmed)

        switch provider {
        case .terminal:
            return prompt
        case .codex,
             .claude:
            return ([base] + modelArguments + [escapedPrompt]).joined(separator: " ")
        case .opencode:
            return ([base] + modelArguments + ["--prompt", escapedPrompt]).joined(separator: " ")
        }
    }

    private static func modelArguments(for provider: AskProvider, model: String?) -> [String] {
        guard let model = model?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty else { return [] }
        let escaped = ShellEscaper.escape(model)
        switch provider {
        case .codex:
            return ["--model", escaped]
        case .claude:
            return ["--model", escaped]
        case .opencode:
            return ["--model", escaped]
        case .terminal:
            return []
        }
    }

    static func resumeCommand(for provider: AskProvider, history: AskHistoryOption, prompt: String) -> String {
        resumeCommand(for: provider, sessionID: history.sessionID, prompt: prompt)
    }

    static func resumeCommand(for provider: AskProvider, sessionID: String, prompt: String) -> String {
        let base = launchCommand(for: provider)
        guard !base.isEmpty else { return "" }
        let escapedID = ShellEscaper.escape(sessionID)
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let escapedPrompt = trimmed.isEmpty ? nil : ShellEscaper.escape(trimmed)

        switch provider {
        case .terminal:
            return trimmed
        case .codex:
            return [base, "resume", escapedID, escapedPrompt].compactMap(\.self).joined(separator: " ")
        case .claude:
            return [base, "--resume", escapedID, escapedPrompt].compactMap(\.self).joined(separator: " ")
        case .opencode:
            if let escapedPrompt {
                return "\(base) --session \(escapedID) --prompt \(escapedPrompt)"
            }
            return "\(base) --session \(escapedID)"
        }
    }

    static func adaptedPrompt(for request: AskDispatchRequest) -> String {
        let prompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let skill = request.skill else { return prompt }

        switch request.provider {
        case .claude:
            return prompt.isEmpty ? "/\(skill.name)" : "/\(skill.name) \(prompt)"
        case .codex,
             .opencode:
            let base = "Use the \(skill.name) skill. Follow the instructions in \(skill.path)."
            return prompt.isEmpty ? base : "\(base) \(prompt)"
        case .terminal:
            return prompt
        }
    }
}
