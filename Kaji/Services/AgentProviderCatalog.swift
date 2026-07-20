import Foundation

struct AgentProviderDescriptor: Hashable {
    let id: String
    let displayName: String
    let iconName: String
}

enum AgentProviderCatalog {
    static let kajiAgentID = "kaji"

    private static let nativeProviders = [
        AgentProviderDescriptor(id: kajiAgentID, displayName: "Kaji Runtime", iconName: "sparkles"),
    ]

    static var routeSources: [NotificationRouteSource] {
        CodingAgentRegistry.shared.definitions.map { NotificationRouteSource(rawValue: $0.displayName) } +
            nativeProviders.map { NotificationRouteSource(rawValue: $0.displayName) }
    }

    static var routeSourceFilters: [NotificationRoutingRule.SourceFilter] {
        CodingAgentRegistry.shared.definitions.map { NotificationRoutingRule.SourceFilter(rawValue: $0.displayName) } +
            nativeProviders.map { NotificationRoutingRule.SourceFilter(rawValue: $0.displayName) }
    }

    static func displayName(for providerID: String) -> String {
        if let definition = CodingAgentRegistry.shared.definition(id: providerID) {
            return definition.displayName
        }
        if let provider = nativeProvider(id: providerID) {
            return provider.displayName
        }
        return providerID.isEmpty ? "Agent" : providerID.capitalized
    }

    static func iconName(for providerID: String) -> String {
        if let definition = CodingAgentRegistry.shared.definition(id: providerID) {
            return definition.iconName
        }
        if let provider = nativeProvider(id: providerID) {
            return provider.iconName
        }
        return "sparkles"
    }

    static func routeSource(for providerID: String) -> NotificationRouteSource? {
        if let definition = CodingAgentRegistry.shared.definition(id: providerID) {
            return NotificationRouteSource(rawValue: definition.displayName)
        }
        if let provider = nativeProvider(id: providerID) {
            return NotificationRouteSource(rawValue: provider.displayName)
        }
        return nil
    }

    static func isAgentRouteSource(_ source: NotificationRouteSource) -> Bool {
        routeSources.contains(source)
    }

    private static func nativeProvider(id: String) -> AgentProviderDescriptor? {
        nativeProviders.first { $0.id == id }
    }
}
