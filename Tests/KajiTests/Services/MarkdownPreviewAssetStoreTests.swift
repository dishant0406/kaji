import Foundation
import Testing

@testable import Kaji

@Suite("MarkdownPreviewAssetStore")
struct MarkdownPreviewAssetStoreTests {
    @Test("serves static shell from custom scheme")
    func servesStaticShell() throws {
        let response = try #require(MarkdownPreviewAssetStore.bundledResponse(for: MarkdownPreviewAssetStore.shellURL))
        let html = String(decoding: response.data, as: UTF8.self)

        #expect(html.contains("kaji-markdown://asset/preview.css"))
        #expect(html.contains("kaji-markdown://asset/preview.js"))
        #expect(!html.contains("{{"))
    }

    @Test("blocks local files outside allowed root")
    func blocksLocalFilesOutsideAllowedRoot() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        let allowed = tempRoot.appendingPathComponent("allowed", isDirectory: true)
        let denied = tempRoot.appendingPathComponent("denied.txt")
        try FileManager.default.createDirectory(at: allowed, withIntermediateDirectories: true)
        try "x".write(to: denied, atomically: true, encoding: .utf8)

        let url = try #require(URL(string: MarkdownPreviewAssetStore.fileURLString(denied)))
        let response = MarkdownPreviewAssetStore.localFileResponse(for: url, allowedRoot: allowed)

        #expect(response == nil)
        try? FileManager.default.removeItem(at: tempRoot)
    }

    @Test("allows local files inside allowed root")
    func allowsLocalFilesInsideAllowedRoot() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = tempRoot.appendingPathComponent("image.txt")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try "hello".write(to: file, atomically: true, encoding: .utf8)

        let url = try #require(URL(string: MarkdownPreviewAssetStore.fileURLString(file)))
        let response = try #require(MarkdownPreviewAssetStore.localFileResponse(for: url, allowedRoot: tempRoot))

        #expect(String(decoding: response.data, as: UTF8.self) == "hello")
        try? FileManager.default.removeItem(at: tempRoot)
    }

    @Test("resolves flattened processed bundle resources")
    func resolvesFlattenedProcessedBundleResources() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = tempRoot.appendingPathComponent("markdown-it.min.js")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try "window.markdownit = true".write(to: file, atomically: true, encoding: .utf8)

        let resolved = MarkdownPreviewAssetStore.bundledFileURL(path: "vendor/markdown-it.min.js", resourceRoot: tempRoot)

        #expect(resolved == file.standardizedFileURL)
        try? FileManager.default.removeItem(at: tempRoot)
    }

    @Test("encodes script literal without raw line separators")
    func encodesScriptLiteral() throws {
        let payload = MarkdownPreviewPayload(
            content: "a\u{2028}b",
            baseURL: nil,
            allowedRootURL: nil,
            allowRemoteImages: false,
            anchors: [],
            theme: MarkdownPreviewTheme(
                bg: "#000000",
                fg: "#FFFFFF",
                muted: "#AAAAAA",
                dim: "#777777",
                surface: "#111111",
                border: "#222222",
                accent: "#333333",
                soft: "#444444"
            ),
            typography: MarkdownPreviewTypography(fontFamily: "SF Mono", fontSize: 15, lineHeight: 1.58)
        )

        let literal = try #require(MarkdownPreviewAssetStore.javaScriptLiteral(payload))

        #expect(literal.contains("\\u2028"))
        #expect(!literal.contains("\u{2028}"))
    }
}
