import Foundation

enum AIGatewayClaudeConnector {
    static func install(settings: AIGatewaySettings, env: [String: String] = ProcessInfo.processInfo.environment) throws {
        let path = settingsPath(env: env)
        let object = try readSettings(path: path)
        let merged = mergedSettings(object, settings: settings)
        try writeSettings(merged, path: path)
    }

    static func mergedSettings(_ object: [String: Any], settings: AIGatewaySettings) -> [String: Any] {
        var copy = object
        removeManagedProfileState(from: &copy, settings: settings)
        let models = settings.models.map { AIGatewayClientModelName.external($0.alias) }
        let existing = object["availableModels"] as? [String] ?? []
        let merged = existing + models.filter { model in !existing.contains(model) }
        copy["availableModels"] = merged.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return copy
    }

    private static func removeManagedProfileState(from settings: inout [String: Any], settings gatewaySettings: AIGatewaySettings) {
        if let helper = settings["apiKeyHelper"] as? String, isManagedHelper(helper) {
            settings.removeValue(forKey: "apiKeyHelper")
        }
        guard var env = settings["env"] as? [String: Any] else { return }
        for key in managedModelEnvKeys {
            env.removeValue(forKey: key)
        }
        for key in managedEndpointEnvKeys where isManagedEndpoint(env[key] as? String, settings: gatewaySettings) {
            env.removeValue(forKey: key)
        }
        if env.isEmpty {
            settings.removeValue(forKey: "env")
        } else {
            settings["env"] = env
        }
    }

    private static func isManagedHelper(_ value: String) -> Bool {
        value.contains("/ai-gateway/claude-code-router/") || value.contains("ccr-claude-code-api-key-")
    }

    private static func isManagedEndpoint(_ value: String?, settings: AIGatewaySettings) -> Bool {
        guard let value else { return false }
        return value == settings.endpointBaseURL
            || value == "http://127.0.0.1:\(settings.normalizedPort)"
            || value == "http://localhost:\(settings.normalizedPort)"
    }

    private static let managedModelEnvKeys = [
        "ANTHROPIC_MODEL",
        "CCR_CLAUDE_CODE_MODEL",
        "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY",
        "CODEXL_CLAUDE_CODE_MODEL",
    ]

    private static let managedEndpointEnvKeys = [
        "ANTHROPIC_API_BASE_URL",
        "ANTHROPIC_BASE_URL",
        "CLAUDE_AGENT_API_BASE_URL",
    ]

    private static func settingsPath(env: [String: String]) -> String {
        let home = env["HOME"] ?? NSHomeDirectory()
        let base = env["CLAUDE_CONFIG_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\((base?.isEmpty == false ? base : nil) ?? "\(home)/.claude")/settings.json"
    }

    private static func readSettings(path: String) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: path) else { return [:] }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try (JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func writeSettings(_ settings: [String: Any], path: String) throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }
}
