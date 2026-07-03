import Foundation
import Testing

@testable import Kaji

struct KajiCodeGraphMCPResourceLocatorTests {
    @Test
    func findsProjectResourceScriptAndSupportFiles() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.writeResources()

        let path = KajiCodeGraphMCPResourceLocator.scriptPath(fileManager: fixture.fileManager, projectRoot: fixture.root)
        let support = KajiCodeGraphMCPResourceLocator.supportDirectory(fileManager: fixture.fileManager, projectRoot: fixture.root)
        let files = KajiCodeGraphMCPResourceLocator.supportFiles(fileManager: fixture.fileManager, projectRoot: fixture.root)

        #expect(path == fixture.script.path)
        #expect(support == fixture.support)
        #expect(files.contains(fixture.support.appendingPathComponent("codegraph-main.js")))
    }
}

private final class Fixture {
    let fileManager = FileManager.default
    let root: URL

    var script: URL {
        root.appendingPathComponent("Kaji/Resources/CodingAgents/CodeGraph/kaji-codegraph-mcp.js")
    }

    var support: URL {
        root.appendingPathComponent("Kaji/Resources/CodingAgents/CodeGraph/kaji-codegraph", isDirectory: true)
    }

    init() throws {
        root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: script.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? fileManager.removeItem(at: root)
    }

    func writeResources() throws {
        try Data("#!/usr/bin/env node\n".utf8).write(to: script)
        try Data("module.exports = {}\n".utf8).write(to: support.appendingPathComponent("codegraph-main.js"))
    }
}
