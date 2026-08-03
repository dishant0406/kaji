import Foundation
import Testing

@testable import Kaji

struct KajiCodeSmokeTesterTests {
    @Test
    func smokeUsesProvidedEnvironmentForEnvNodeScripts() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: bin, withIntermediateDirectories: true)
        let node = bin.appendingPathComponent("node")
        let kajicode = root.appendingPathComponent("kajicode")
        try Data("#!/bin/sh\necho KajiCode 9.9.9\n".utf8).write(to: node)
        try Data("#!/usr/bin/env node\n".utf8).write(to: kajicode)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: node.path)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: kajicode.path)

        await #expect(throws: KajiCodeInstallError.self) {
            _ = try await KajiCodeSmokeTester.smoke(
                binaryURL: kajicode,
                expectedVersion: nil,
                environment: ["HOME": root.path, "PATH": "/usr/bin:/bin"]
            )
        }

        let output = try await KajiCodeSmokeTester.smoke(
            binaryURL: kajicode,
            expectedVersion: "9.9.9",
            environment: ["HOME": root.path, "PATH": "\(bin.path):/usr/bin:/bin"]
        )
        #expect(output == "KajiCode 9.9.9")
    }
}
