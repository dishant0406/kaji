import Foundation
import Testing

@testable import Kaji

struct KajiAgentHostURIResolverTests {
    @Test
    func readsPercentEncodedWorkspaceFile() throws {
        let root = try temporaryDirectory()
        let file = root.appendingPathComponent("docs/read me.txt")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "hello".write(to: file, atomically: true, encoding: .utf8)

        let result = KajiAgentHostURIResolver.resolve(
            KajiAgentRPCFrame(type: "host_uri_request", url: "kaji-file://docs/read%20me.txt", operation: "read"),
            rootPath: root.path
        )

        #expect(result.content == "hello")
        #expect(result.contentType == "text/plain")
        #expect(result.error == nil)
    }

    @Test
    func rejectsUnsupportedOperationBeforeWorkspaceLookup() {
        let result = KajiAgentHostURIResolver.resolve(
            KajiAgentRPCFrame(type: "host_uri_request", url: "kaji-file://README.md", operation: "write"),
            rootPath: nil
        )

        #expect(result.error == "Unsupported Kaji URI request.")
    }

    @Test
    func rejectsOutsideWorkspacePath() throws {
        let root = try temporaryDirectory()

        let result = KajiAgentHostURIResolver.resolve(
            KajiAgentRPCFrame(type: "host_uri_request", url: "kaji-file://../outside.txt", operation: "read"),
            rootPath: root.path
        )

        #expect(result.error == "File path is outside the active Kaji worktree.")
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
