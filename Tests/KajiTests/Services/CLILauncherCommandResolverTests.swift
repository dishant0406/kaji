import Foundation
import Testing
@testable import Kaji

struct CLILauncherCommandResolverTests {
    @Test
    func leavesUnknownCommandUnchanged() {
        #expect(CLILauncherCommandResolver.resolve("missing-agent --flag") == "missing-agent --flag")
    }

    @Test
    func preservesAbsoluteCommand() {
        #expect(CLILauncherCommandResolver.resolve("/usr/bin/env pi") == "/usr/bin/env pi")
    }

    @Test
    func resolvesBareCommandAndPreservesArguments() throws {
        let fixture = try CommandResolverFixture()
        defer { fixture.cleanup() }
        try fixture.writeExecutable("codex", in: fixture.realBin)

        let command = CLILauncherCommandResolver.resolve(
            "codex --model gpt-5 'hello world'",
            env: fixture.env(path: [fixture.realBin]),
            homeDirectory: fixture.home.path,
            fileManager: fixture.fileManager
        )

        #expect(command == "\(ShellEscaper.escape(fixture.realBin.appendingPathComponent("codex").path)) --model gpt-5 'hello world'")
    }

    @Test
    func skipsLegacyKajiShimDirectory() throws {
        let fixture = try CommandResolverFixture()
        defer { fixture.cleanup() }
        let shimBin = fixture.home
            .appendingPathComponent(".kaji", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        try fixture.fileManager.createDirectory(at: shimBin, withIntermediateDirectories: true)
        try fixture.writeExecutable("codex", in: shimBin)
        try fixture.writeExecutable("codex", in: fixture.realBin)

        let command = CLILauncherCommandResolver.resolve(
            "codex",
            env: fixture.env(path: [shimBin, fixture.realBin]),
            homeDirectory: fixture.home.path,
            fileManager: fixture.fileManager
        )

        #expect(command == ShellEscaper.escape(fixture.realBin.appendingPathComponent("codex").path))
    }

    @Test
    func resolvesKajicodeDeveloperOverrideBeforePath() throws {
        let fixture = try CommandResolverFixture()
        defer { fixture.cleanup() }
        try fixture.writeExecutable("kajicode", in: fixture.realBin)
        let override = fixture.realBin.appendingPathComponent("kajicode")

        let command = CLILauncherCommandResolver.resolve(
            "kajicode --model gpt-5",
            env: [
                "PATH": "/usr/bin",
                "SHELL": fixture.shell.path,
                KajiCodePaths.devBinaryKey: override.path,
            ],
            homeDirectory: fixture.home.path,
            fileManager: fixture.fileManager
        )

        #expect(command == "\(ShellEscaper.escape(override.path)) --model gpt-5")
    }

    @Test
    func leavesQuotedAndWrapperCommandsUnchanged() throws {
        let fixture = try CommandResolverFixture()
        defer { fixture.cleanup() }
        try fixture.writeExecutable("codex", in: fixture.realBin)

        let env = ["PATH": fixture.realBin.path]
        #expect(CLILauncherCommandResolver.resolve(
            "'codex' --flag",
            env: env,
            homeDirectory: fixture.home.path
        ) == "'codex' --flag")
        #expect(CLILauncherCommandResolver.resolve(
            "env codex --flag",
            env: env,
            homeDirectory: fixture.home.path
        ) == "env codex --flag")
        #expect(CLILauncherCommandResolver.resolve(
            "FOO=1 codex",
            env: env,
            homeDirectory: fixture.home.path
        ) == "FOO=1 codex")
    }

    @Test
    func resolvesConfiguredAbsoluteExecutable() throws {
        let fixture = try CommandResolverFixture()
        defer { fixture.cleanup() }
        try fixture.writeExecutable("kajicode", in: fixture.realBin)
        let executable = fixture.realBin.appendingPathComponent("kajicode")

        let url = CLILauncherCommandResolver.resolvedExecutableURL(
            in: "\(executable.path) --model gpt-5",
            env: fixture.env(path: [fixture.realBin]),
            homeDirectory: fixture.home.path,
            fileManager: fixture.fileManager
        )

        #expect(url?.path == executable.path)
    }
}

private struct CommandResolverFixture {
    let fileManager = FileManager.default
    let root: URL
    let home: URL
    let realBin: URL
    let shell: URL

    init() throws {
        root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        realBin = root.appendingPathComponent("real-bin", isDirectory: true)
        shell = root.appendingPathComponent("shell")
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: realBin, withIntermediateDirectories: true)
        try writeShell()
    }

    func env(path directories: [URL]) -> [String: String] {
        [
            "SHELL": shell.path,
            "PATH": directories.map(\.path).joined(separator: ":"),
        ]
    }

    func writeExecutable(_ name: String, in directory: URL) throws {
        let url = directory.appendingPathComponent(name)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    func cleanup() {
        try? fileManager.removeItem(at: root)
    }

    private func writeShell() throws {
        try Data("""
        #!/bin/sh
        whence() {
          name=""
          for arg in "$@"; do
            name="$arg"
          done
          old_ifs="$IFS"
          IFS=:
          for dir in $PATH; do
            if [ -x "$dir/$name" ]; then
              printf '%s\\n' "$dir/$name"
            fi
          done
          IFS="$old_ifs"
        }
        if [ "$1" = "-lc" ]; then
          eval "$2"
        else
          eval "$1"
        fi
        """.utf8).write(to: shell)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shell.path)
    }
}
