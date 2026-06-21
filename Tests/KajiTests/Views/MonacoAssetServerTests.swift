import Foundation
import Testing

@testable import Kaji

@Suite("Monaco asset server", .serialized)
struct MonacoAssetServerTests {
    @Test("resolves files inside root")
    func resolvesFilesInsideRoot() throws {
        let root = try makeRoot()
        let fileURL = root.appendingPathComponent("index.html")
        try "ok".write(to: fileURL, atomically: true, encoding: .utf8)
        let resolved = MonacoAssetServer.resolvedFileURL(for: "/index.html", root: root)
        #expect(resolved?.path == fileURL.standardizedFileURL.resolvingSymlinksInPath().path)
    }

    @Test("rejects traversal outside root")
    func rejectsTraversal() throws {
        let root = try makeRoot()
        #expect(MonacoAssetServer.resolvedFileURL(for: "/../Package.swift", root: root) == nil)
        #expect(MonacoAssetServer.resolvedFileURL(for: "/%2E%2E/Package.swift", root: root) == nil)
    }

    @Test("serves existing asset")
    func servesAsset() throws {
        let root = try makeRoot()
        try "body".write(to: root.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        let response = MonacoAssetServer.response(for: "GET /index.html HTTP/1.1\r\nHost: localhost\r\n\r\n", root: root)
        let text = String(data: response.data, encoding: .utf8) ?? ""
        #expect(text.contains("HTTP/1.1 200 OK"))
        #expect(text.contains("Cache-Control: no-cache"))
        #expect(text.contains("body"))
    }

    @Test("serves hashed assets with long cache lifetime")
    func servesHashedAssetsWithLongCacheLifetime() throws {
        let root = try makeRoot()
        try "body".write(to: root.appendingPathComponent("main-abc123.js"), atomically: true, encoding: .utf8)
        let response = MonacoAssetServer.response(for: "GET /main-abc123.js HTTP/1.1\r\nHost: localhost\r\n\r\n", root: root)
        let text = String(data: response.data, encoding: .utf8) ?? ""
        #expect(text.contains("Cache-Control: public, max-age=31536000, immutable"))
    }

    private func makeRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
