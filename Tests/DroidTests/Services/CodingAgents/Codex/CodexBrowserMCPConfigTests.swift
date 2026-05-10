import Testing

@testable import Droid

struct CodexBrowserMCPConfigTests {
    @Test
    func buildsRuntimeConfigArguments() {
        let descriptor = DroidBrowserMCPServerDescriptor(
            name: "droid-browser",
            command: "node",
            arguments: ["/tmp/droid-browser-mcp.js"],
            environment: ["DROID_BROWSER_BROKER_URL": "http://127.0.0.1:1"]
        )

        let args = CodexBrowserMCPConfig.arguments(for: descriptor)

        #expect(args.contains("mcp_servers.droid-browser.command=\"node\""))
        #expect(args.contains("mcp_servers.droid-browser.args=[\"/tmp/droid-browser-mcp.js\"]"))
        #expect(args.contains("mcp_servers.droid-browser.env={DROID_BROWSER_BROKER_URL=\"http://127.0.0.1:1\"}"))
    }
}
