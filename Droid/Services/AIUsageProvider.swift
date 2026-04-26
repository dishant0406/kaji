import Foundation

protocol AIUsageProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var iconName: String { get }

    func fetchUsageSnapshot() async -> AIProviderUsageSnapshot
}

extension AIUsageProvider {
    func fetchUsageSnapshot() async -> AIProviderUsageSnapshot {
        snapshot(state: .unavailable(message: "Coming soon"))
    }

    func snapshot(
        state: AIProviderUsageState,
        rows: [AIUsageMetricRow] = [],
        fetchedAt: Date = Date()
    ) -> AIProviderUsageSnapshot {
        AIProviderUsageSnapshot(
            providerID: id,
            providerName: displayName,
            providerIconName: iconName,
            fetchedAt: fetchedAt,
            state: state,
            rows: rows
        )
    }
}

enum AIUsageAuthError: Error {
    case missingCredentials
}
