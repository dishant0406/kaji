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
            env: ["PATH": fixture.realBin.path],
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
            env: ["PATH": "\(shimBin.path):\(fixture.realBin.path)"],
            homeDirectory: fixture.home.path,
            fileManager: fixture.fileManager
        )

        #expect(command == ShellEscaper.escape(fixture.realBin.appendingPathComponent("codex").path))
    }

    @Test
    func leavesQuotedAndWrapperCommandsUnchanged() throws {
        let fixture = try CommandResolverFixture()
        defer { fixture.cleanup() }
        try fixture.writeExecutable("codex", in: fixture.realBin)

        let env = ["PATH": fixture.realBin.path]
        #expect(CLILauncherCommandResolver.resolve("'codex' --flag", env: env, homeDirectory: fixture.home.path) == "'codex' --flag")
        #expect(CLILauncherCommandResolver.resolve("env codex --flag", env: env, homeDirectory: fixture.home.path) == "env codex --flag")
        #expect(CLILauncherCommandResolver.resolve("FOO=1 codex", env: env, homeDirectory: fixture.home.path) == "FOO=1 codex")
    }
}

private struct CommandResolverFixture {
    let fileManager = FileManager.default
    let root: URL
    let home: URL
    let realBin: URL

    init() throws {
        root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        realBin = root.appendingPathComponent("real-bin", isDirectory: true)
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: realBin, withIntermediateDirectories: true)
    }

    func writeExecutable(_ name: String, in directory: URL) throws {
        let url = directory.appendingPathComponent(name)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    func cleanup() {
        try? fileManager.removeItem(at: root)
    }
}
