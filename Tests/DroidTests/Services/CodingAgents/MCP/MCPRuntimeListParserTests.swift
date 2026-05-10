import Testing

@testable import Droid

struct MCPRuntimeListParserTests {
    @Test
    func parsesCodexMCPListTables() {
        let output = """
        Name           Command    Args      Env     Cwd  Status   Auth       
        computer-use   ./App      mcp       -       .    enabled  Unsupported
        droid-browser  /bin/mcp   -         TOKEN=* -    enabled  Unsupported

        Name   Url                        Bearer Token Env Var  Status   Auth 
        figma  https://mcp.figma.com/mcp  -                     enabled  OAuth
        """

        let records = MCPRuntimeListParser.parseCodexList(output)

        #expect(records.map(\.name) == ["computer-use", "droid-browser", "figma"])
        #expect(records.first { $0.name == "figma" }?.url == "https://mcp.figma.com/mcp")
        #expect(records.first { $0.name == "figma" }?.authSummary == "OAuth")
    }

    @Test
    func parsesOpenCodeMCPList() {
        let output = """
        ┌  MCP Servers
        │
        ●  ✓ figma connected
        │      https://mcp.figma.com/mcp
        │
        ●  ✓ droid-browser connected
        │      /Users/test/.droid/bin/droid-browser-mcp
        └  2 server(s)
        """

        let records = MCPRuntimeListParser.parseOpenCodeList(output)

        #expect(records.map(\.name) == ["figma", "droid-browser"])
        #expect(records.allSatisfy { $0.status == "connected" })
    }
}
