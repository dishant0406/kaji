import Testing

@testable import Kaji

struct KajiAgentInspectorItemTests {
    @Test
    func toolItemUsesFullOutputBeforePreview() {
        var message = KajiAgentMessage(kind: .tool, title: "bash", detail: "")
        message.preview = "preview"
        message.fullOutput = "full"

        let item = KajiAgentInspectorItem.tool(message)

        #expect(item.title == "bash")
        #expect(item.subtitle == "Output available")
        #expect(message.kajiAgentToolOutput == "full")
    }

    @Test
    func failedToolItemHasFailureSubtitle() {
        var message = KajiAgentMessage(kind: .tool, title: "bash", detail: "")
        message.isError = true

        let item = KajiAgentInspectorItem.tool(message)

        #expect(item.subtitle == "Failed")
    }

    @Test
    func toolGroupItemSummarizesActionCount() {
        let group = KajiAgentToolGroup(tools: [
            KajiAgentMessage(kind: .tool, title: "read", detail: ""),
            KajiAgentMessage(kind: .tool, title: "bash", detail: ""),
        ])

        let item = KajiAgentInspectorItem.toolGroup(group)

        #expect(item.title == "Tools called (2)")
        #expect(item.subtitle == "2 actions")
    }
}
