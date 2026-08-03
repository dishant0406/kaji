import Foundation
import Testing
@testable import Kaji

struct KajiCodeInstallStoreTests {
    @Test
    func writesAndReadsManifestUnderAppSupportOverride() throws {
        let fixture = try KajiCodeFixture()
        defer { fixture.cleanup() }
        let manifest = fixture.manifest()

        try KajiCodeInstallStore.write(manifest, env: fixture.env, fileManager: fixture.fileManager)
        let loaded = KajiCodeInstallStore.read(env: fixture.env, fileManager: fixture.fileManager)

        #expect(loaded == manifest)
        #expect(fixture.fileManager.fileExists(atPath: KajiCodePaths.manifestURL(env: fixture.env).path))
    }

    @Test
    func runtimeLocatorPrefersDeveloperOverrideThenManagedBinary() throws {
        let fixture = try KajiCodeFixture()
        defer { fixture.cleanup() }
        let manifest = fixture.manifest()
        let managed = try fixture.writeManagedExecutable(for: manifest)
        let override = try fixture.writeExecutable("override-kajicode")
        try KajiCodeInstallStore.write(manifest, env: fixture.env, fileManager: fixture.fileManager)

        let managedResolution = fixture.resolve()
        let overrideResolution = fixture.resolve(
            env: fixture.env.merging([KajiCodePaths.devBinaryKey: override.path]) { _, new in new }
        )

        #expect(managedResolution?.binaryURL.path == managed.path)
        #expect(managedResolution?.source == .managed)
        #expect(overrideResolution?.binaryURL.path == override.path)
        #expect(overrideResolution?.source == .developerOverride)
    }

    @Test
    func runtimeLocatorUsesShellResolvedExecutable() throws {
        let fixture = try KajiCodeFixture()
        defer { fixture.cleanup() }
        let shellFixture = try ShellExecutableFixture()
        defer { shellFixture.cleanup() }
        let executable = try shellFixture.writeExecutable("kajicode")

        let resolution = fixture.resolve(env: fixture.env.merging(shellFixture.env()) { _, new in new })
        let noPathResolution = fixture.resolve(
            env: fixture.env.merging(shellFixture.env(path: [shellFixture.secondBin])) { _, new in new }
        )

        #expect(resolution?.binaryURL.path == executable.path)
        #expect(resolution?.source == .path)
        #expect(noPathResolution == nil)
    }

    @Test
    func runtimeLocatorRejectsSymlinkOverride() throws {
        let fixture = try KajiCodeFixture()
        defer { fixture.cleanup() }
        let executable = try fixture.writeExecutable("real-kajicode")
        let symlink = fixture.root.appendingPathComponent("linked-kajicode")
        try fixture.fileManager.createSymbolicLink(at: symlink, withDestinationURL: executable)

        let resolution = fixture.resolve(
            env: fixture.env.merging([
                "PATH": "",
                "SHELL": "/usr/bin/false",
                KajiCodePaths.devBinaryKey: symlink.path,
            ]) { _, new in new }
        )

        #expect(resolution == nil)
    }

    @Test
    func invalidManagedIdentityFallsBackToPath() throws {
        let fixture = try KajiCodeFixture()
        defer { fixture.cleanup() }
        let invalidManifest = fixture.manifest(version: "../escape")
        try KajiCodeInstallStore.write(invalidManifest, env: fixture.env, fileManager: fixture.fileManager)
        let shellFixture = try ShellExecutableFixture()
        defer { shellFixture.cleanup() }
        let executable = try shellFixture.writeExecutable("kajicode")

        let resolution = fixture.resolve(
            env: fixture.env.merging(shellFixture.env()) { _, new in new }
        )

        #expect(KajiCodePaths.binaryURL(for: invalidManifest, env: fixture.env) == nil)
        #expect(resolution?.binaryURL.path == executable.path)
        #expect(resolution?.source == .path)
    }

    @Test
    func installerStateRequiresCurrentPlatformAndValidDigest() throws {
        let fixture = try KajiCodeFixture()
        defer { fixture.cleanup() }
        let wrongPlatform = fixture.manifest(platform: "unsupported-platform")
        try KajiCodeInstallStore.write(wrongPlatform, env: fixture.env, fileManager: fixture.fileManager)

        #expect(KajiCodeInstaller.state(env: fixture.env, fileManager: fixture.fileManager) == .needsRepair(
            "Managed KajiCode platform does not match this Mac."
        ))
        #expect(KajiCodePaths.installDirectory(
            version: "1.0.0",
            platform: KajiCodePlatform.current,
            sha256: "not-a-digest",
            env: fixture.env
        ) == nil)
    }

    @Test
    func runtimeLocatorUsesConfiguredExecutableCommand() throws {
        let fixture = try KajiCodeFixture()
        defer { fixture.cleanup() }
        let executable = try fixture.writeExecutable("kajicode")

        let resolution = KajiCodeRuntimeLocator.resolve(
            configuredCommand: "\(executable.path) --model gpt-5",
            env: fixture.env,
            homeDirectory: fixture.home.path,
            fileManager: fixture.fileManager
        )

        #expect(resolution?.binaryURL.path == executable.path)
        #expect(resolution?.source == .path)
    }
}

private struct KajiCodeFixture {
    let fileManager = FileManager.default
    let root: URL
    let home: URL
    let env: [String: String]

    init() throws {
        root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        env = ["KAJI_APP_SUPPORT_DIR": root.appendingPathComponent("support", isDirectory: true).path]
    }

    func manifest(
        version: String = "0.4.2",
        platform: String = KajiCodePlatform.current,
        sha256: String = String(repeating: "a", count: 64)
    ) -> KajiCodeInstallManifest {
        KajiCodeInstallManifest(
            activeVersion: version,
            previousVersion: nil,
            protocolVersion: 1,
            platform: platform,
            sourceURL: URL(string: "https://example.com/kajicode.tar.gz")!,
            sha256: sha256,
            installedAt: Date(timeIntervalSince1970: 1_800_000_000),
            smokeOutput: "KajiCode 0.4.2",
            channelURL: URL(string: "https://example.com/kaji-channel.json")!
        )
    }

    func resolve(env: [String: String]? = nil) -> KajiCodeRuntimeResolution? {
        KajiCodeRuntimeLocator.resolve(
            env: env ?? self.env,
            homeDirectory: home.path,
            fileManager: fileManager
        )
    }

    func writeManagedExecutable(for manifest: KajiCodeInstallManifest) throws -> URL {
        let directory = try #require(KajiCodePaths.installDirectory(
            version: manifest.activeVersion,
            platform: manifest.platform,
            sha256: manifest.sha256,
            env: env
        ))
        return try writeExecutable("kajicode", in: directory)
    }

    func writeExecutable(_ name: String, in directory: URL? = nil) throws -> URL {
        let directory = directory ?? root
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    func cleanup() {
        try? fileManager.removeItem(at: root)
    }
}
