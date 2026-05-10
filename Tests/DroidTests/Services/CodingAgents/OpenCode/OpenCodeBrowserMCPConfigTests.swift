import Foundation
import Testing

@testable import Droid

struct OpenCodeBrowserMCPConfigTests {
    @Test
    func buildsLocalConfig() throws {
        let descriptor = DroidBrowserMCPServerDescriptor(
            name: "droid-browser",
            command: "node",
            arguments: ["browser.js"],
            environment: [:]
        )

        let config = OpenCodeBrowserMCPConfig.config(for: descriptor)
        let mcp = try #require(config["mcp"] as? [String: Any])
        let browser = try #require(mcp["droid-browser"] as? [String: Any])

        #expect(browser["type"] as? String == "local")
        #expect(browser["enabled"] as? Bool == true)
    }

    @Test
    func writesProjectIndependentConfig() throws {
        let fileManager = FileManager.default
        let home = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: home) }
        let descriptor = DroidBrowserMCPServerDescriptor(
            name: "droid-browser",
            command: "/tmp/droid-browser-mcp",
            arguments: [],
            environment: ["DROID_BROWSER_BROKER_URL": "http://127.0.0.1:1"]
        )

        let url = try #require(OpenCodeBrowserMCPConfig.write(
            descriptor: descriptor,
            homeDirectory: home.path,
            fileManager: fileManager
        ))
        let text = try String(contentsOf: url, encoding: .utf8)

        #expect(url.path.hasSuffix(".droid/agent-configs/opencode-browser-mcp.json"))
        #expect(text.contains("droid-browser"))
        #expect(text.contains("DROID_BROWSER_BROKER_URL"))
    }
}
