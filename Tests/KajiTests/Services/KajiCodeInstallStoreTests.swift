import Foundation
import Testing
@testable import Kaji

struct KajiCodeInstallStoreTests {
    @Test
    func writesAndReadsManifestUnderAppSupportOverride() throws {
        let fixture = try KajiCodeFixture()
        defer { fixture.cleanup() }
        let manifest = fixture.manifest(binaryPath: "/tmp/kajicode")

        try KajiCodeInstallStore.write(manifest, env: fixture.env, fileManager: fixture.fileManager)
        let loaded = KajiCodeInstallStore.read(env: fixture.env, fileManager: fixture.fileManager)

        #expect(loaded == manifest)
        #expect(fixture.fileManager.fileExists(atPath: KajiCodePaths.manifestURL(env: fixture.env).path))
    }

    @Test
    func runtimeLocatorPrefersDeveloperOverrideThenManagedBinary() throws {
        let fixture = try KajiCodeFixture()
        defer { fixture.cleanup() }
        let managed = try fixture.writeExecutable("managed-kajicode")
        let override = try fixture.writeExecutable("override-kajicode")
        try KajiCodeInstallStore.write(
            fixture.manifest(binaryPath: managed.path),
            env: fixture.env,
            fileManager: fixture.fileManager
        )

        let managedResolution = KajiCodeRuntimeLocator.resolve(
            env: fixture.env,
            homeDirectory: fixture.home.path,
            fileManager: fixture.fileManager
        )
        let overrideResolution = KajiCodeRuntimeLocator.resolve(
            env: fixture.env.merging([KajiCodePaths.devBinaryKey: override.path]) { _, new in new },
            homeDirectory: fixture.home.path,
            fileManager: fixture.fileManager
        )

        #expect(managedResolution?.binaryURL.path == managed.path)
        #expect(managedResolution?.source == .managed)
        #expect(overrideResolution?.binaryURL.path == override.path)
        #expect(overrideResolution?.source == .developerOverride)
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

    func manifest(binaryPath: String) -> KajiCodeInstallManifest {
        KajiCodeInstallManifest(
            activeVersion: "0.4.2",
            previousVersion: nil,
            protocolVersion: 1,
            platform: "macos-arm64",
            sourceURL: URL(string: "https://example.com/kajicode.tar.gz")!,
            sha256: String(repeating: "a", count: 64),
            installedAt: Date(timeIntervalSince1970: 1_800_000_000),
            binaryPath: binaryPath,
            smokeOutput: "KajiCode 0.4.2",
            channelURL: URL(string: "https://example.com/kaji-channel.json")!
        )
    }

    func writeExecutable(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    func cleanup() {
        try? fileManager.removeItem(at: root)
    }
}
