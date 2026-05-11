import Foundation
import Testing

@testable import Kaji

struct GhosttyRuntimeResourceLocatorTests {
    @Test
    func bundledRuntimePathWins() throws {
        let root = try temporaryRuntimeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let bundleURL = root.appendingPathComponent("Bundle", isDirectory: true)
        let bundledPath = bundleURL.appendingPathComponent("ghostty", isDirectory: true)
        try createRuntimeTree(at: bundledPath)

        let result = GhosttyRuntimeResourceLocator.preferredResourceDirectory(
            bundleResourceURL: bundleURL,
            currentEnv: "/tmp/external",
            externalCandidates: ["/tmp/fallback"]
        )

        #expect(result == bundledPath.path)
    }

    @Test
    func fallsBackToCurrentEnvWhenBundledRuntimeMissing() throws {
        let root = try temporaryRuntimeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let envPath = root.appendingPathComponent("external", isDirectory: true)
        try createRuntimeTree(at: envPath)

        let result = GhosttyRuntimeResourceLocator.preferredResourceDirectory(
            bundleResourceURL: root.appendingPathComponent("Bundle", isDirectory: true),
            currentEnv: envPath.path,
            externalCandidates: []
        )

        #expect(result == envPath.path)
    }

    private func temporaryRuntimeRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func createRuntimeTree(at url: URL) throws {
        try FileManager.default.createDirectory(at: url.appendingPathComponent("shell-integration"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: url.appendingPathComponent("terminfo/78"), withIntermediateDirectories: true)
    }
}
