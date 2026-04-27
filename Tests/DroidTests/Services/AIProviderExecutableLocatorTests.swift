import Foundation
import Testing

@testable import Droid

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
}
