import Foundation

struct CodingAgentUsageAdapter: AIUsageProvider {
    let module: any CodingAgentModule & AIUsageProvider

    var id: String { module.id }
    var displayName: String { module.displayName }
    var iconName: String { module.iconName }

    func fetchUsageSnapshot() async -> AIProviderUsageSnapshot {
        await module.fetchUsageSnapshot()
    }
}
