import Testing

@testable import Kaji

struct TerminalEnvironmentPolicyTests {
    @Test
    func stripsNoColorFromInheritedEnvironment() {
        let result = TerminalEnvironmentPolicy.sanitizedEnvironment(
            from: [
                "NO_COLOR": "1",
                "COLORTERM": "truecolor",
                "PATH": "/usr/bin",
            ]
        )

        #expect(result["NO_COLOR"] == nil)
        #expect(result["COLORTERM"] == "truecolor")
        #expect(result["PATH"] == "/usr/bin")
    }

    @Test
    @MainActor
    func startupCommandUsesInteractiveLoginShell() {
        let command = GhosttyShellLaunchCommand.startupCommand("codex 'hello'", environment: ["SHELL": "/bin/zsh"])

        #expect(command.contains(" -l -i -c "))
        #expect(command.contains("codex"))
    }

    @Test
    func defaultTerminalUsesUserShellForGhosttyIntegrationDetection() {
        let command = GhosttyShellLaunchCommand.interactiveShell(environment: ["SHELL": "/bin/zsh"])

        #expect(command == "/bin/zsh -l")
    }
}
