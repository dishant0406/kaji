import Foundation
import Testing

@testable import Kaji

@Suite("MarkdownPreviewLinkResolver")
struct MarkdownPreviewLinkResolverTests {
    @Test("resolves relative local file links inside root")
    func relativeLocalFile() throws {
        let root = temporaryRoot()
        let docs = root.appendingPathComponent("docs", isDirectory: true)
        let target = docs.appendingPathComponent("guide.md")
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        try "# Guide".write(to: target, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let action = MarkdownPreviewLinkResolver.resolve(
            MarkdownPreviewLinkRequest(href: "guide.md", resolvedURL: nil),
            documentURL: docs.appendingPathComponent("README.md"),
            allowedRoot: root
        )

        #expect(action == .localFile(target.standardizedFileURL.resolvingSymlinksInPath()))
    }

    @Test("blocks local file links outside root")
    func blocksOutsideRoot() throws {
        let root = temporaryRoot()
        let outsideRoot = temporaryRoot()
        let outside = outsideRoot.appendingPathComponent("secret.md")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
        try "secret".write(to: outside, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outsideRoot)
        }

        let action = MarkdownPreviewLinkResolver.resolve(
            MarkdownPreviewLinkRequest(href: outside.path, resolvedURL: outside.absoluteString),
            documentURL: root.appendingPathComponent("README.md"),
            allowedRoot: root
        )

        #expect(action == .blockedLocalFile(outside.standardizedFileURL.resolvingSymlinksInPath()))
    }

    @Test("reports missing local files inside root")
    func missingLocalFile() throws {
        let root = temporaryRoot()
        let missing = root.appendingPathComponent("missing.md")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let action = MarkdownPreviewLinkResolver.resolve(
            MarkdownPreviewLinkRequest(href: "missing.md", resolvedURL: nil),
            documentURL: root.appendingPathComponent("README.md"),
            allowedRoot: root
        )

        #expect(action == .missingLocalFile(missing.standardizedFileURL.resolvingSymlinksInPath()))
    }

    @Test("keeps anchors inside preview")
    func anchor() {
        let action = MarkdownPreviewLinkResolver.resolve(
            MarkdownPreviewLinkRequest(href: "#usage", resolvedURL: nil),
            documentURL: nil,
            allowedRoot: nil
        )

        #expect(action == .anchor("usage"))
    }

    @Test("opens http links externally")
    func externalHTTP() throws {
        let url = try #require(URL(string: "https://example.com/docs"))

        let action = MarkdownPreviewLinkResolver.resolve(
            MarkdownPreviewLinkRequest(href: url.absoluteString, resolvedURL: nil),
            documentURL: nil,
            allowedRoot: nil
        )

        #expect(action == .external(url))
    }

    private func temporaryRoot() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
