import Testing

@testable import Kaji

struct CodingAgentProcessPatternKillerTests {
    @Test
    func buildsTerminateArguments() {
        #expect(CodingAgentProcessPatternKiller.arguments(pattern: "opencode", signal: .terminate) == ["-TERM", "-f", "opencode"])
    }

    @Test
    func buildsKillArguments() {
        #expect(CodingAgentProcessPatternKiller.arguments(pattern: "codex", signal: .kill) == ["-KILL", "-f", "codex"])
    }
}
