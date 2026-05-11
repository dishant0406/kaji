import Testing

@testable import Kaji

struct CodexBrowserMCPConfigTests {
    @Test
    func buildsRuntimeConfigArguments() {
        let descriptor = KajiBrowserMCPServerDescriptor(
            name: "kaji-browser",
            command: "node",
            arguments: ["/tmp/kaji-browser-mcp.js"],
            environment: ["KAJI_BROWSER_BROKER_URL": "http://127.0.0.1:1"]
        )

        let args = CodexBrowserMCPConfig.arguments(for: descriptor)

        #expect(args.contains("mcp_servers.kaji-browser.command=\"node\""))
        #expect(args.contains("mcp_servers.kaji-browser.args=[\"/tmp/kaji-browser-mcp.js\"]"))
        #expect(args.contains("mcp_servers.kaji-browser.env={KAJI_BROWSER_BROKER_URL=\"http://127.0.0.1:1\"}"))
    }
}
