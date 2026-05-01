import Foundation
import Testing

@testable import Droid

struct AskCommandDispatcherTests {
    @Test
    @MainActor
    func startupCommandUsesProviderNativePromptShape() {
        let codex = AskCommandDispatcher.startupCommand(for: .codex, prompt: "whats this repo about")
        let claude = AskCommandDispatcher.startupCommand(for: .claude, prompt: "hello")
        let opencode = AskCommandDispatcher.startupCommand(for: .opencode, prompt: "hello world")
        let empty = AskCommandDispatcher.startupCommand(for: .opencode, prompt: "")

        #expect(commandExecutableName(codex) == "codex")
        #expect(codex.hasSuffix("'whats this repo about'"))
        #expect(commandExecutableName(claude) == "claude")
        #expect(claude.hasSuffix(" hello"))
        #expect(commandExecutableName(opencode) == "opencode")
        #expect(opencode.contains("--prompt 'hello world'"))
        #expect(!empty.isEmpty)
        #expect(!empty.contains("--prompt"))
    }

    @Test
    @MainActor
    func resumeCommandUsesProviderNativeShape() {
        let history = AskHistoryOption(
            provider: .codex,
            sessionID: "session one",
            title: "Fix tests",
            detail: "Codex in muxy",
            projectPath: nil,
            updatedAt: Date()
        )

        let codex = AskCommandDispatcher.resumeCommand(for: .codex, history: history, prompt: "continue")
        let claude = AskCommandDispatcher.resumeCommand(for: .claude, history: history, prompt: "continue")
        let opencode = AskCommandDispatcher.resumeCommand(for: .opencode, history: history, prompt: "continue")

        #expect(codex.contains("resume 'session one' continue"))
        #expect(claude.contains("--resume 'session one' continue"))
        #expect(opencode.contains("--session 'session one' --prompt continue"))
    }

    @Test
    @MainActor
    func completionNotificationWrapperPreservesCommandAndProviderPayload() {
        let wrapped = AskCommandDispatcher.commandWithCompletionNotification("opencode --prompt hello", provider: .opencode)

        #expect(wrapped.contains("opencode --prompt hello"))
        #expect(wrapped.contains("DROID_HOOK_CLIENT_PATH"))
        #expect(wrapped.contains("ask-complete"))
        #expect(wrapped.contains("opencode"))
        #expect(wrapped.contains("OpenCode"))
        #expect(wrapped.contains("Session completed"))
        #expect(wrapped.contains("droid_status=$?"))
        #expect(!wrapped.contains("; status=$?"))
        #expect(wrapped.contains("exec \"${SHELL:-/bin/zsh}\" -i"))
        #expect(!wrapped.contains("exit $status"))
        #expect(!wrapped.contains("python"))
    }

    @Test
    @MainActor
    func skillsAdaptPromptsPerProvider() {
        let skill = AskSkillOption(
            name: "copywriting",
            title: "Write copy",
            detail: "Agents skill",
            path: "/tmp/copywriting/SKILL.md",
            source: "Agents"
        )

        #expect(AskCommandDispatcher.adaptedPrompt(for: request(provider: .claude, prompt: "write a hero", skill: skill)) == "/copywriting write a hero")
        #expect(AskCommandDispatcher.adaptedPrompt(for: request(provider: .codex, prompt: "write a hero", skill: skill)).contains("Use the copywriting skill"))
        #expect(AskCommandDispatcher.adaptedPrompt(for: request(provider: .opencode, prompt: "", skill: skill)).contains("/tmp/copywriting/SKILL.md"))
    }

    private func request(provider: AskProvider, prompt: String, skill: AskSkillOption?) -> AskDispatchRequest {
        AskDispatchRequest(
            prompt: prompt,
            project: Project(name: "muxy", path: "/tmp/muxy"),
            worktree: Worktree(name: "main", path: "/tmp/muxy", isPrimary: true),
            provider: provider,
            sessionMode: .bestMatch,
            session: nil,
            history: nil,
            skill: skill
        )
    }

    private func commandExecutableName(_ command: String) -> String? {
        guard let token = command.split(whereSeparator: \.isWhitespace).first else { return nil }
        return URL(fileURLWithPath: String(token).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))).lastPathComponent
    }
}
