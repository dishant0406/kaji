import Foundation

enum MCPServerRuntimeMetadataReader {
    static func enriched(_ server: MCPServer, location: MCPServerConfigLocation) -> MCPServer {
        guard location.url.lastPathComponent == "mcp-cache.json" else { return server }
        guard let data = try? Data(contentsOf: location.url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = root["servers"] as? [String: Any],
              let cached = servers[server.name] as? [String: Any]
        else { return server }
        var server = server
        server.toolNames = toolNames(from: cached)
        server.runtimeSummary = runtimeSummary(toolCount: server.toolNames.count, cachedAt: cached["cachedAt"] as? Double)
        return server
    }

    private static func toolNames(from cached: [String: Any]) -> [String] {
        guard let tools = cached["tools"] as? [[String: Any]] else { return [] }
        return tools.compactMap { $0["name"] as? String }.sorted()
    }

    private static func runtimeSummary(toolCount: Int, cachedAt: Double?) -> String {
        guard let cachedAt else { return "\(toolCount) runtime tools cached" }
        let date = Date(timeIntervalSince1970: cachedAt / 1000)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "\(toolCount) runtime tools cached \(formatter.localizedString(for: date, relativeTo: Date()))"
    }
}
