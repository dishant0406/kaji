import Testing

@testable import Droid

struct AIActivityProcessMatcherTests {
    @Test
    func matchesWhenAnyProcessBelongsToProvider() {
        let processNames = ["zsh", "node", "codex"]
        #expect(AIActivityProcessMatcher.matches(providerID: "codex", processNames: processNames))
    }

    @Test
    func ignoresShellLeaderWhenProviderExited() {
        let processNames = ["zsh", "login"]
        #expect(!AIActivityProcessMatcher.matches(providerID: "codex", processNames: processNames))
    }
}
