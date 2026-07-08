import Foundation

enum AIGatewayConfigValidator {
    static func validate(_ settings: AIGatewaySettings) -> String? {
        let enabled = settings.providers.filter(\.isEnabled)
        guard !enabled.isEmpty else { return "Enable at least one AI Gateway provider." }
        if let invalid = enabled.first(where: { $0.isCustom && $0.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return "Set a base URL for \(invalid.name)."
        }
        if let azure = enabled
            .first(where: { $0.kind == .azure && $0.azureOpenAIBaseURL.isEmpty })
        {
            return "Set an Azure resource or endpoint for \(azure.name)."
        }
        let enabledProviders = Set(enabled.map(\.id))
        let hasRoute = settings.models.contains { model in
            model.routes.contains { route in
                guard let provider = route.split(separator: "/", maxSplits: 1).first.map(String.init) else { return false }
                return enabledProviders.contains(provider)
            }
        }
        return hasRoute ? nil : "Add at least one model route that uses an enabled provider."
    }
}
