import Foundation

enum AIGatewayClientModelName {
    static func external(_ alias: String) -> String {
        "Fusion/\(AIGatewayModelAliasPolicy.sanitized(alias))"
    }

    static func first(in settings: AIGatewaySettings) -> String {
        external(settings.models.first?.alias ?? "main")
    }
}
