import Foundation
import Testing

@testable import Kaji

struct KajiBrowserMCPServerDescriptorTests {
    @Test
    func descriptorKeepsOnlyBrowserEnvironment() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.writeScript()

        let descriptor = KajiBrowserMCPServerDescriptor.current(
            environment: [
                "KAJI_BROWSER_BROKER_URL": "http://127.0.0.1:1234",
                "KAJI_BROWSER_MCP_TOKEN": "token",
                "PATH": "/bin",
            ],
            fileManager: fixture.fileManager,
            projectRoot: fixture.root
        )

        #expect(descriptor?.name == "kaji-browser")
        #expect(descriptor?.command == "node")
        #expect(descriptor?.environment["PATH"] == nil)
        #expect(descriptor?.environment["KAJI_BROWSER_MCP_TOKEN"] == "token")
    }
}

private final class Fixture {
    let fileManager = FileManager.default
    let root: URL

    init() throws {
        root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? fileManager.removeItem(at: root)
    }

    func writeScript() throws {
        let path = root.appendingPathComponent("Kaji/Resources/CodingAgents/Browser", isDirectory: true)
        try fileManager.createDirectory(at: path, withIntermediateDirectories: true)
        try Data("#!/usr/bin/env node\n".utf8).write(to: path.appendingPathComponent("kaji-browser-mcp.js"))
    }
}
