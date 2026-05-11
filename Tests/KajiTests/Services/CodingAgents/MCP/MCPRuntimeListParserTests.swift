import Testing

@testable import Kaji

struct MCPRuntimeListParserTests {
    @Test
    func parsesCodexMCPListTables() {
        let output = """
        Name           Command    Args      Env     Cwd  Status   Auth       
        computer-use   ./App      mcp       -       .    enabled  Unsupported
        kaji-browser  /bin/mcp   -         TOKEN=* -    enabled  Unsupported

        Name   Url                        Bearer Token Env Var  Status   Auth 
        figma  https://mcp.figma.com/mcp  -                     enabled  OAuth
        """

        let records = MCPRuntimeListParser.parseCodexList(output)

        #expect(records.map(\.name) == ["computer-use", "kaji-browser", "figma"])
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
        ●  ✓ kaji-browser connected
        │      /Users/test/.kaji/bin/kaji-browser-mcp
        └  2 server(s)
        """

        let records = MCPRuntimeListParser.parseOpenCodeList(output)

        #expect(records.map(\.name) == ["figma", "kaji-browser"])
        #expect(records.allSatisfy { $0.status == "connected" })
    }
}
