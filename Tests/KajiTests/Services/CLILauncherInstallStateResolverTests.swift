import Foundation
import Testing

@testable import Kaji

struct CLILauncherInstallStateResolverTests {
    @Test
    func resolvesInstallStateOffMain() async throws {
        let fixture = try ShellExecutableFixture()
        defer { fixture.cleanup() }
        _ = try fixture.writeExecutable("codex")

        let installed = await CLILauncherInstallStateResolver.isInstalled(
            executableNames: ["codex"],
            env: fixture.env(),
            homeDirectory: fixture.home.path
        )

        #expect(installed)
    }

    @Test
    func resolvesInstallStateFromConfiguredCommand() async throws {
        let fixture = try ShellExecutableFixture()
        defer { fixture.cleanup() }
        let executable = try fixture.writeExecutable("codex")

        let installed = await CLILauncherInstallStateResolver.isInstalled(
            for: "codex",
            command: "\(executable.path) --model gpt-5"
        )

        #expect(installed)
    }
}
