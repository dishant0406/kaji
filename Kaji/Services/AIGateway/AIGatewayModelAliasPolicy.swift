import Foundation

enum AIGatewayModelAliasPolicy {
    private static let reserved: Set<String> = ["main", "subagent", "background", "unknown"]

    static func sanitized(_ alias: String) -> String {
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "kaji-main" }
        return reserved.contains(trimmed) ? "kaji-\(trimmed)" : trimmed
    }

    static func sanitize(settings: inout AIGatewaySettings) {
        settings.models = settings.models.map { model in
            var copy = model
            copy.alias = sanitized(model.alias)
            return copy
        }
    }
}
