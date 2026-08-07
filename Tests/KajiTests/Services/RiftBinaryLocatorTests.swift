import Foundation
import Testing

@testable import Kaji

@Suite("Rift binary locator")
struct RiftBinaryLocatorTests {
    @Test("honors env override without touching the resource bundle")
    func honorsEnvironmentOverride() throws {
        let fixture = try RiftBinaryFixture()
        defer { fixture.cleanup() }
        setenv("KAJI_RIFT_BINARY_PATH", fixture.binary.path, 1)
        defer { unsetenv("KAJI_RIFT_BINARY_PATH") }

        let url = RiftBinaryLocator.url()

        #expect(url?.path == fixture.binary.path)
    }

    @Test("does not crash when the resource bundle path is invalid")
    func toleratesMissingBundleResource() {
        unsetenv("KAJI_RIFT_BINARY_PATH")

        let url = RiftBinaryLocator.url()

        #expect(url == nil || FileManager.default.isExecutableFile(atPath: url!.path))
    }
}

private final class RiftBinaryFixture {
    let binary: URL

    init() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kaji-rift-locator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        binary = dir.appendingPathComponent("rift")
        FileManager.default.createFile(atPath: binary.path, contents: Data("#!/bin/sh\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: binary.deletingLastPathComponent())
    }
}
