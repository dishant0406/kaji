import Testing

@testable import Droid

struct AskCommandDispatcherTests {
    @Test
    @MainActor
    func startupCommandUsesProviderNativePromptShape() {
        let codex = AskCommandDispatcher.startupCommand(for: .codex, prompt: "whats this repo about")
        let claude = AskCommandDispatcher.startupCommand(for: .claude, prompt: "hello")
        let opencode = AskCommandDispatcher.startupCommand(for: .opencode, prompt: "hello world")

        #expect(codex.hasPrefix("codex"))
        #expect(codex.hasSuffix("'whats this repo about'"))
        #expect(claude.hasPrefix("claude"))
        #expect(claude.hasSuffix(" hello"))
        #expect(opencode.hasPrefix("opencode"))
        #expect(opencode.contains("--prompt 'hello world'"))
    }
}
