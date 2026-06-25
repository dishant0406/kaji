import Foundation
import Testing

@testable import Kaji

struct KajiBrowserMCPToolCatalogTests {
    @Test
    func exposesPlaywrightCompatibleToolsWithoutRuntimeDependency() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let browser = root.appendingPathComponent("Kaji/Resources/CodingAgents/Browser/kaji-browser")
        let catalog = try String(contentsOf: browser.appendingPathComponent("playwright-compatible-tools.js"), encoding: .utf8)
        let kajiTools = try String(contentsOf: browser.appendingPathComponent("kaji-tools.js"), encoding: .utf8)

        for name in ["browser_click", "browser_snapshot", "browser_tabs", "browser_file_upload", "browser_network_requests"] {
            #expect(catalog.contains(name))
        }
        #expect(kajiTools.contains("playwright-compatible-tools"))
        #expect(!kajiTools.contains("@playwright/mcp"))
        #expect(!kajiTools.contains("cdp-endpoint"))
    }

    @Test
    func exposesAccessibilityToolBeforeBrowserToolExpansion() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let browser = root.appendingPathComponent("Kaji/Resources/CodingAgents/Browser/kaji-browser")
        let tools = try String(contentsOf: browser.appendingPathComponent("kaji-tools.js"), encoding: .utf8)
        let catalog = try String(contentsOf: browser.appendingPathComponent("tool-catalog.js"), encoding: .utf8)
        let availability = try String(contentsOf: browser.appendingPathComponent("availability.js"), encoding: .utf8)
        let errors = try String(contentsOf: browser.appendingPathComponent("browser-errors.js"), encoding: .utf8)

        #expect(tools.contains("const allTools"))
        #expect(tools.contains("async function list()"))
        #expect(tools.contains("return allTools"))
        #expect(!tools.contains("if (!status.accessible) return availabilityTools"))
        #expect(catalog.contains("kaji_browser_accessible"))
        #expect(catalog.contains("kaji_browser_navigate"))
        #expect(catalog.contains("kaji_browser_file_upload"))
        #expect(catalog.contains("kaji_browser_network_requests"))
        #expect(availability.contains("session_missing"))
        #expect(availability.contains("broker_unreachable"))
        #expect(errors.contains("toolErrorResult"))
        #expect(errors.contains("recovery"))
    }

    @Test
    func fullCatalogIsAvailableWithoutBrowserSession() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let script = root.appendingPathComponent("Kaji/Resources/CodingAgents/Browser/kaji-browser/main.js")
        guard FileManager.default.fileExists(atPath: script.path) else { return }

        let output = try runNode("""
        const { dispatch } = require('\(script.path)');
        (async () => {
          const result = await dispatch('tools/list', {});
          console.log(JSON.stringify(result.tools.map(tool => tool.name)));
        })();
        """)
        let data = try #require(output.data(using: .utf8))
        let tools = try #require(JSONSerialization.jsonObject(with: data) as? [String])

        #expect(tools.contains("kaji_browser_accessible"))
        #expect(tools.contains("kaji_browser_navigate"))
        #expect(tools.contains("kaji_browser_screenshot"))
        #expect(tools.contains("kaji_browser_file_upload"))
        #expect(tools.contains("browser_navigate"))
        #expect(tools.contains("browser_snapshot"))
        #expect(tools.contains("browser_take_screenshot"))
    }

    @Test
    func unavailableBrowserToolReturnsStructuredError() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let script = root.appendingPathComponent("Kaji/Resources/CodingAgents/Browser/kaji-browser/main.js")
        guard FileManager.default.fileExists(atPath: script.path) else { return }

        let output = try runNode("""
        process.env.HOME = '/tmp/kaji-browser-empty-home';
        process.env.KAJI_BROWSER_BROKER_URL = '';
        process.env.KAJI_BROWSER_MCP_TOKEN = '';
        process.env.KAJI_BROWSER_SESSION_ID = '';
        const { dispatch } = require('\(script.path)');
        (async () => {
          const result = await dispatch('tools/call', { name: 'kaji_browser_navigate', arguments: { url: 'https://kaji.sh' } });
          console.log(JSON.stringify(result));
        })();
        """)
        let data = try #require(output.data(using: .utf8))
        let result = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let content = try #require(result["content"] as? [[String: Any]])
        let text = try #require(content.first?["text"] as? String)

        #expect(result["isError"] as? Bool == true)
        #expect(text.contains(#""code""#))
        #expect(text.contains(#""recovery""#))
    }

    @Test
    func keepsMCPProcessAliveUntilInitializeArrives() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/env") else { return }
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let script = root.appendingPathComponent("Kaji/Resources/CodingAgents/Browser/kaji-browser-mcp.js")
        guard FileManager.default.fileExists(atPath: script.path) else { return }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", script.path]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()

        try process.run()
        usleep(300_000)
        #expect(process.isRunning)

        let request = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}"# + "\n"
        try input.fileHandleForWriting.write(contentsOf: Data(request.utf8))
        let response = output.fileHandleForReading.availableData
        let text = String(decoding: response, as: UTF8.self)

        #expect(text.contains(#""id":1"#))
        #expect(text.contains(#""serverInfo""#))
        #expect(process.isRunning)

        process.terminate()
        process.waitUntilExit()
    }

    private func runNode(_ code: String) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", "-e", code]
        process.standardOutput = output
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
