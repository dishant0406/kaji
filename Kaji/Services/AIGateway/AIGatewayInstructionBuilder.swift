import Foundation

enum AIGatewayInstructionBuilder {
    static func claude(settings: AIGatewaySettings, token: String) -> String {
        [
            "export ANTHROPIC_BASE_URL=\"\(settings.anthropicBaseURL)\"",
            "export ANTHROPIC_AUTH_TOKEN=\"\(token)\"",
            "claude --model \(AIGatewayClientModelName.first(in: settings))",
        ].joined(separator: "\n")
    }

    static func codex(settings: AIGatewaySettings, token: String) -> String {
        [
            "export KAJI_GATEWAY_TOKEN=\"\(token)\"",
            "codex --model \(AIGatewayClientModelName.first(in: settings))",
        ].joined(separator: "\n")
    }

    static func genericOpenAI(settings: AIGatewaySettings, token: String) -> String {
        [
            "Base URL: \(settings.openAIBaseURL)",
            "Authorization: Bearer \(token)",
        ].joined(separator: "\n")
    }

    static func genericAnthropic(settings: AIGatewaySettings, token: String) -> String {
        [
            "Base URL: \(settings.anthropicBaseURL)",
            "x-api-key: \(token)",
        ].joined(separator: "\n")
    }
}
