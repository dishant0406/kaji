import Foundation
import Testing

@testable import Droid

struct CLILauncherInstallStateResolverTests {
    @Test
    func resolvesInstallStateOffMain() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)

        let executable = bin.appendingPathComponent("codex")
        try "#!/bin/sh\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let installed = await CLILauncherInstallStateResolver.isInstalled(
            executableNames: ["codex"],
            env: ["PATH": bin.path],
            homeDirectory: root.path
        )

        #expect(installed)
    }
}
