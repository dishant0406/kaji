import Foundation

extension AIGatewayRuntimeController {
    func launchArguments(settings: AIGatewaySettings) -> [String] {
        ["serve", "--host", settings.bindAddress, "--port", String(managementPort(settings)), "--no-open"]
    }

    func launchEnvironment(settings: AIGatewaySettings, token: String) -> [String: String] {
        var env = AIGatewayCredentialEnvironment.variables(settings: settings, token: token)
        env["CCR_INTERNAL_HOME_DIR"] = AIGatewayClaudeCodeRouterPaths.runtimeHome().path
        env["CCR_INTERNAL_APP_DATA_DIR"] = AIGatewayClaudeCodeRouterPaths.appData().path
        env["CCR_INTERNAL_USER_DATA_DIR"] = AIGatewayClaudeCodeRouterPaths.userData().path
        env["CCR_WEB_AUTH_TOKEN"] = token
        env["CCR_GATEWAY_ENTRY"] = AIGatewayClaudeCodeRouterPaths.gatewayEntryURL().path
        env["KAJI_CCR_PACKAGE_DIR"] = AIGatewayClaudeCodeRouterPaths.packageDirectory().path
        env["KAJI_CCR_OPENAI_RESPONSES_PLUGIN"] = AIGatewayClaudeCodeRouterPaths.openAIResponsesPluginURL().path
        return env
    }

    func managementPort(_ settings: AIGatewaySettings) -> Int {
        min(settings.normalizedPort + 2, 65535)
    }
}
