import Foundation

enum AIGatewayCodexConnector {
    static func install(settings: AIGatewaySettings, env: [String: String] = ProcessInfo.processInfo.environment) throws {
        let path = CodexAgentModule.configPath(env: env)
        let existing = FileManager.default.fileExists(atPath: path) ? try String(contentsOfFile: path, encoding: .utf8) : ""
        try write(mergedConfig(existing, settings: settings), path: path)
    }

    static func mergedConfig(_ existing: String, settings: AIGatewaySettings) -> String {
        var lines = existing.components(separatedBy: .newlines)
        lines = removeGatewayProviderBlock(from: lines)
        lines.removeAll { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("model =") || trimmed.hasPrefix("model_provider =")
        }
        while lines.last?.isEmpty == true {
            lines.removeLast()
        }
        if !lines.isEmpty {
            lines.append("")
        }
        lines.append("model = \"\(escape(AIGatewayClientModelName.first(in: settings)))\"")
        lines.append("model_provider = \"kaji_gateway\"")
        lines.append("")
        lines.append("[model_providers.kaji_gateway]")
        lines.append("name = \"Kaji AI Gateway\"")
        lines.append("base_url = \"\(escape(settings.openAIBaseURL))\"")
        lines.append("env_key = \"KAJI_GATEWAY_TOKEN\"")
        lines.append("wire_api = \"responses\"")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func removeGatewayProviderBlock(from lines: [String]) -> [String] {
        var output = [String]()
        var skipping = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "[model_providers.kaji_gateway]" {
                skipping = true
                continue
            }
            if skipping, trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
                skipping = false
            }
            if !skipping {
                output.append(line)
            }
        }
        return output
    }

    private static func write(_ content: String, path: String) throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
