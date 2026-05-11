import Foundation
import Testing

@testable import Kaji

struct KajiBrowserMCPResourceLocatorTests {
    @Test
    func findsProjectResourceScript() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.writeScript()

        let path = KajiBrowserMCPResourceLocator.scriptPath(
            fileManager: fixture.fileManager,
            projectRoot: fixture.root
        )
        let support = KajiBrowserMCPResourceLocator.supportDirectory(
            fileManager: fixture.fileManager,
            projectRoot: fixture.root
        )
        let files = KajiBrowserMCPResourceLocator.supportFiles(
            fileManager: fixture.fileManager,
            projectRoot: fixture.root
        )

        #expect(path == fixture.script.path)
        #expect(support == fixture.support)
        #expect(files.contains(fixture.support.appendingPathComponent("main.js")))
    }
}

private final class Fixture {
    let fileManager = FileManager.default
    let root: URL

    var script: URL {
        root.appendingPathComponent("Kaji/Resources/CodingAgents/Browser/kaji-browser-mcp.js")
    }

    var support: URL {
        root.appendingPathComponent("Kaji/Resources/CodingAgents/Browser/kaji-browser", isDirectory: true)
    }

    init() throws {
        root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: script.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? fileManager.removeItem(at: root)
    }

    func writeScript() throws {
        try Data("#!/usr/bin/env node\n".utf8).write(to: script)
        try Data("module.exports = {}\n".utf8).write(to: support.appendingPathComponent("main.js"))
    }
}
