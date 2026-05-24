import Foundation
import Testing

@testable import Kaji

struct TerminalSelectionActionResolverTests {
    @Test
    func resolvesHttpsURL() throws {
        let action = TerminalSelectionActionResolver.action(
            from: "https://ghostty.org/docs/config/reference",
            workingDirectory: "/tmp"
        )

        #expect(action?.title == "Open Link")
        #expect(action?.url.absoluteString == "https://ghostty.org/docs/config/reference")
    }

    @Test
    func resolvesRelativeFilePath() throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("README.md")
        try "test".write(to: file, atomically: true, encoding: .utf8)

        let action = TerminalSelectionActionResolver.action(from: "README.md", workingDirectory: directory.path)

        #expect(action?.title == "Open File")
        #expect(action?.url.path == file.path)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
