import Foundation
import Testing

@testable import Kaji

struct PiBrowserMCPConfigTests {
    @Test
    func buildsMCPServerConfig() throws {
        let descriptor = KajiBrowserMCPServerDescriptor(
            name: "kaji-browser",
            command: "node",
            arguments: ["browser.js"],
            environment: [:]
        )

        let config = PiBrowserMCPConfig.config(for: descriptor)
        let servers = try #require(config["mcpServers"] as? [String: Any])
        let browser = try #require(servers["kaji-browser"] as? [String: Any])

        #expect(browser["command"] as? String == "node")
        #expect(browser["directTools"] as? Bool == true)
    }

    @Test
    func writesProjectIndependentConfig() throws {
        let fileManager = FileManager.default
        let home = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: home) }
        let descriptor = KajiBrowserMCPServerDescriptor(
            name: "kaji-browser",
            command: "/tmp/kaji-browser-mcp",
            arguments: [],
            environment: ["KAJI_BROWSER_BROKER_URL": "http://127.0.0.1:1"]
        )

        let url = try #require(PiBrowserMCPConfig.write(
            descriptor: descriptor,
            homeDirectory: home.path,
            fileManager: fileManager
        ))
        let text = try String(contentsOf: url, encoding: .utf8)

        #expect(url.path.hasSuffix(".kaji/agent-configs/pi-browser-mcp.json"))
        #expect(text.contains("kaji-browser"))
        #expect(text.contains("KAJI_BROWSER_BROKER_URL"))
    }

}
