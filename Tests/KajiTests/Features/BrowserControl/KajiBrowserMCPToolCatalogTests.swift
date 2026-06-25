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
}
