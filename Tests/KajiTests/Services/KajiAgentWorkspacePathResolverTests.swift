import Foundation
import Testing

@testable import Kaji

struct KajiAgentWorkspacePathResolverTests {
    @Test
    func resolvesRelativePathInsideWorkspace() throws {
        let root = try temporaryDirectory()
        let file = root.appendingPathComponent("Sources/App.swift")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: file.path, contents: Data())

        let resolved = KajiAgentWorkspacePathResolver.resolve("Sources/App.swift", rootPath: root.path)

        #expect(resolved == file.standardizedFileURL.resolvingSymlinksInPath().path)
    }

    @Test
    func rejectsSiblingPrefixEscape() throws {
        let root = try temporaryDirectory()
        let sibling = root.deletingLastPathComponent().appendingPathComponent(root.lastPathComponent + "-other")
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)

        let resolved = KajiAgentWorkspacePathResolver.resolve(sibling.path, rootPath: root.path)

        #expect(resolved == nil)
    }

    @Test
    func rejectsSymlinkEscape() throws {
        let root = try temporaryDirectory()
        let outside = try temporaryDirectory()
        let outsideFile = outside.appendingPathComponent("secret.txt")
        let link = root.appendingPathComponent("secret-link.txt")
        try "secret".write(to: outsideFile, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outsideFile)

        let resolved = KajiAgentWorkspacePathResolver.resolve("secret-link.txt", rootPath: root.path)

        #expect(resolved == nil)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
