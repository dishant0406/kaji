import Foundation
import Testing

@testable import Kaji

struct KajiBrowserControlCommandTests {
    @Test
    func preservesStructuredArguments() throws {
        let command = try #require(KajiBrowserControlCommand(
            body: """
            {
              "sessionId": "session",
              "action": "browser_take_screenshot",
              "arguments": {
                "fullPage": true,
                "width": 1200,
                "fields": [{ "target": "e1", "value": "hello" }],
                "values": ["one", "two"]
              }
            }
            """,
            defaultSessionID: "default"
        ))

        #expect(command.sessionID == "session")
        #expect(command.action == "screenshot")
        #expect(command.arguments.bool("fullPage") == true)
        #expect(command.arguments.int("width") == 1200)
        #expect(command.arguments.objects("fields").count == 1)
        #expect(command.arguments.strings("values") == ["one", "two"])
    }

    @Test
    func resolvesPlaywrightToolAliases() {
        #expect(KajiBrowserControlActionAlias.resolve("browser_click") == "click")
        #expect(KajiBrowserControlActionAlias.resolve("browser_fill_form") == "fill_form")
        #expect(KajiBrowserControlActionAlias.resolve("kaji_browser_click") == "kaji_browser_click")
    }
}
