import Foundation
import Testing

@testable import Kaji

struct ShellExecutionEnvironmentResolverTests {
    @Test
    func resolvesInteractiveShellPathEnvironment() throws {
        let fixture = try ShellExecutableFixture()
        defer { fixture.cleanup() }
        var env = fixture.env(path: [fixture.firstBin])
        let interactivePath = "\(fixture.interactiveBin.path):/usr/bin:/bin"
        env["KAJI_TEST_INTERACTIVE_PATH"] = interactivePath
        env["KAJI_TEST_LOGIN_ENV_FAIL"] = "1"

        let environment = ShellExecutionEnvironmentResolver.resolve(
            env: env,
            homeDirectory: fixture.home.path,
            fileManager: fixture.fileManager
        )

        #expect(environment["PATH"] == interactivePath)
    }

    @Test
    func exposesOnlyPathForMCPEnvironment() {
        let environment = ShellExecutionEnvironmentResolver.mcpEnvironment(from: [
            "PATH": "/shell/bin:/usr/bin",
            "SECRET_TOKEN": "never-write-this",
        ])

        #expect(environment == ["PATH": "/shell/bin:/usr/bin"])
    }
}
