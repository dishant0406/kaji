import Foundation

@MainActor
enum AIGatewayLaunchEnvironment {
    static func variables(
        store: AIGatewaySettingsStore = .shared,
        installState: AIGatewayInstallState? = nil
    ) -> [(key: String, value: String)] {
        guard store.settings.isEnabled else { return [] }
        let state = installState ?? AIGatewayClaudeCodeRouterInstaller.state()
        guard case .installed = state else { return [] }
        let token = store.ensureToken()
        guard !token.isEmpty else { return [] }
        return [
            (key: "KAJI_GATEWAY_TOKEN", value: token),
            (key: "ANTHROPIC_BASE_URL", value: store.settings.anthropicBaseURL),
            (key: "ANTHROPIC_AUTH_TOKEN", value: token),
            (key: "GATEWAY_TOKEN", value: token),
        ]
    }
}
