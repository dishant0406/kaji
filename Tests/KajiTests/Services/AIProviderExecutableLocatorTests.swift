import Foundation
import Testing

@testable import Kaji

struct AIProviderExecutableLocatorTests {
    @Test
    func resolvesExecutableFromPathEnvironment() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)

        let executable = bin.appendingPathComponent("codex")
        try "#!/bin/sh\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let path = AIProviderExecutableLocator.resolvePath(
            for: "codex",
            env: ["PATH": bin.path],
            homeDirectory: root.path
        )

        #expect(path == executable.path)
    }

    @Test
    func resolvesExecutableFromNvmInstall() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let versionBin = root
            .appendingPathComponent(".nvm")
            .appendingPathComponent("versions")
            .appendingPathComponent("node")
            .appendingPathComponent("v22.15.0")
            .appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: versionBin, withIntermediateDirectories: true)

        let executable = versionBin.appendingPathComponent("codex")
        try "#!/bin/sh\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let path = AIProviderExecutableLocator.resolvePath(
            for: "codex",
            env: [:],
            homeDirectory: root.path
        )

        #expect(path == executable.path)
    }

    @Test
    func resolvesExecutableFromOpenCodeInstall() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bin = root.appendingPathComponent(".opencode/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)

        let executable = bin.appendingPathComponent("opencode")
        try "#!/bin/sh\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let path = AIProviderExecutableLocator.resolvePath(
            for: "opencode",
            env: [:],
            homeDirectory: root.path
        )

        #expect(path == executable.path)
    }
    @Test
    func prefersNewestNvmExecutableOverOlderPathExecutable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let oldBin = root.appendingPathComponent("old-bin")
        let latestBin = root
            .appendingPathComponent(".nvm/versions/node/v22.20.0/bin")
        try FileManager.default.createDirectory(at: oldBin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: latestBin, withIntermediateDirectories: true)

        let oldExecutable = oldBin.appendingPathComponent("codex")
        let latestExecutable = latestBin.appendingPathComponent("codex")
        try "#!/bin/sh\nexit 0\n".write(to: oldExecutable, atomically: true, encoding: .utf8)
        try "#!/bin/sh\nexit 0\n".write(to: latestExecutable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: oldExecutable.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: latestExecutable.path)

        let path = AIProviderExecutableLocator.resolvePath(
            for: "codex",
            env: ["PATH": oldBin.path],
            homeDirectory: root.path
        )

        #expect(path == latestExecutable.path)
    }
}
