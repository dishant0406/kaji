import Foundation
import Testing

@Suite("Monaco first paint", .serialized)
struct MonacoFirstPaintTests {
    @Test("runtime source has inline transparent background before scripts")
    func runtimeSourceHasInlineBackgroundBeforeScripts() throws {
        let html = try html(at: "KajiMonacoRuntime/index.html")
        try expectCriticalStyle(in: html)
        let styleIndex = try #require(html.range(of: "<style>")?.lowerBound)
        let scriptIndex = try #require(html.range(of: "<script")?.lowerBound)
        #expect(styleIndex < scriptIndex)
    }

    @Test("built runtime keeps inline transparent background before scripts")
    func builtRuntimeKeepsInlineBackgroundBeforeScripts() throws {
        let html = try html(at: "Kaji/Resources/MonacoEditor/index.html")
        try expectCriticalStyle(in: html)
        let styleIndex = try #require(html.range(of: "<style>")?.lowerBound)
        let scriptIndex = try #require(html.range(of: "<script")?.lowerBound)
        #expect(styleIndex < scriptIndex)
    }

    private func expectCriticalStyle(in html: String) throws {
        #expect(html.contains("html,body,#editor"))
        #expect(html.contains("background:transparent"))
        #expect(html.contains("overflow:hidden"))
    }

    private func html(at path: String) throws -> String {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(path)
        try #require(FileManager.default.fileExists(atPath: url.path))
        return try String(contentsOf: url, encoding: .utf8)
    }
}
