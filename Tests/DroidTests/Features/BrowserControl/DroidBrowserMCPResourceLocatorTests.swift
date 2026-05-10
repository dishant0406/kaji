import Foundation
import Testing

@testable import Droid

struct DroidBrowserMCPResourceLocatorTests {
    @Test
    func findsProjectResourceScript() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.writeScript()

        let path = DroidBrowserMCPResourceLocator.scriptPath(
            fileManager: fixture.fileManager,
            projectRoot: fixture.root
        )

        #expect(path == fixture.script.path)
    }
}

private final class Fixture {
    let fileManager = FileManager.default
    let root: URL

    var script: URL {
        root.appendingPathComponent("Droid/Resources/CodingAgents/Browser/droid-browser-mcp.js")
    }

    init() throws {
        root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: script.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    func cleanup() {
        try? fileManager.removeItem(at: root)
    }

    func writeScript() throws {
        try Data("#!/usr/bin/env node\n".utf8).write(to: script)
    }
}
