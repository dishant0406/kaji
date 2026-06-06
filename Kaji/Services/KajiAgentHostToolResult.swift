import Foundation

enum KajiAgentHostToolResult {
    static func text(_ value: String, details: KajiAgentJSONValue? = nil) -> KajiAgentToolResult {
        KajiAgentToolResult(content: [KajiAgentContentBlock(type: "text", text: value)], details: details, isError: false)
    }

    static func error(_ value: String, details: KajiAgentJSONValue? = nil) -> KajiAgentToolResult {
        KajiAgentToolResult(content: [KajiAgentContentBlock(type: "text", text: value)], details: details, isError: true)
    }
}
