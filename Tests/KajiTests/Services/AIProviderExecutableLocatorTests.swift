import Foundation
import Testing

@testable import Kaji

struct AIProviderExecutableLocatorTests {
    @Test
    func resolvesExecutableThroughShellPath() throws {
        let fixture = try ShellExecutableFixture()
        defer { fixture.cleanup() }
        let executable = try fixture.writeExecutable("codex")

        let path = AIProviderExecutableLocator.resolvePath(
            for: "codex",
            env: fixture.env(),
            homeDirectory: fixture.home.path
        )

        #expect(path == executable.path)
    }

    @Test
    func preferredRealPathSkipsExcludedShellResult() throws {
        let fixture = try ShellExecutableFixture()
        defer { fixture.cleanup() }
        _ = try fixture.writeExecutable("codex", in: fixture.firstBin)
        let executable = try fixture.writeExecutable("codex", in: fixture.secondBin)

        let path = AIProviderExecutableLocator.preferredRealPath(
            for: "codex",
            env: fixture.env(path: [fixture.firstBin, fixture.secondBin]),
            homeDirectory: fixture.home.path,
            fileManager: fixture.fileManager,
            excluding: fixture.firstBin
        )

        #expect(path == executable.path)
    }

    @Test
    func ignoresDirectoryGuessesWhenShellCannotResolveExecutable() throws {
        let fixture = try ShellExecutableFixture()
        defer { fixture.cleanup() }
        let guessedBin = fixture.home.appendingPathComponent(".local/bin", isDirectory: true)
        try fixture.fileManager.createDirectory(at: guessedBin, withIntermediateDirectories: true)
        _ = try fixture.writeExecutable("claude", in: guessedBin)

        let path = AIProviderExecutableLocator.resolvePath(
            for: "claude",
            env: fixture.env(path: [fixture.firstBin]),
            homeDirectory: fixture.home.path
        )

        #expect(path == nil)
    }

    @Test
    func fallsBackToInteractiveShellLookup() throws {
        let fixture = try ShellExecutableFixture()
        defer { fixture.cleanup() }
        let executable = try fixture.writeExecutable("kajicode", in: fixture.interactiveBin)
        var env = fixture.env(path: [fixture.firstBin])
        env["KAJI_TEST_INTERACTIVE_PATH"] = fixture.interactiveBin.path

        let path = AIProviderExecutableLocator.resolvePath(
            for: "kajicode",
            env: env,
            homeDirectory: fixture.home.path
        )

        #expect(path == executable.path)
    }

    @Test
    func resolvesExecutableFromExplicitManagedDirectory() throws {
        let fixture = try ShellExecutableFixture()
        defer { fixture.cleanup() }
        let managedBin = fixture.root.appendingPathComponent("managed-bin", isDirectory: true)
        try fixture.fileManager.createDirectory(at: managedBin, withIntermediateDirectories: true)
        let executable = try fixture.writeExecutable("node", in: managedBin)

        let path = AIProviderExecutableLocator.resolvePath(
            for: "node",
            env: fixture.env(path: [fixture.firstBin]),
            homeDirectory: fixture.home.path,
            fileManager: fixture.fileManager,
            extraDirectories: [managedBin.path]
        )

        #expect(path == executable.path)
    }
}
