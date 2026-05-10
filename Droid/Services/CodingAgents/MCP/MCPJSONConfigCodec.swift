import Foundation

enum MCPJSONConfigCodec {
    static func read(data: Data, format: MCPServerConfigFormat) throws -> [MCPServer] {
        guard !data.isEmpty else { return [] }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MCPServerConfigError.invalidRoot
        }
        return servers(from: root, format: format)
    }

    static func write(servers: [MCPServer], existingData: Data?, format: MCPServerConfigFormat) throws -> Data {
        let root = try rootObject(from: existingData)
        let updated = merge(servers: servers, into: root, format: format)
        return try JSONSerialization.data(withJSONObject: updated, options: [.prettyPrinted, .sortedKeys])
    }

    private static func rootObject(from data: Data?) throws -> [String: Any] {
        guard let data, !data.isEmpty else { return [:] }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MCPServerConfigError.invalidRoot
        }
        return root
    }

    private static func servers(from root: [String: Any], format: MCPServerConfigFormat) -> [MCPServer] {
        switch format {
        case .standardJSON:
            standardServers(from: root["mcpServers"] as? [String: Any] ?? [:])
        case .openCodeJSON:
            openCodeServers(from: root["mcp"] as? [String: Any] ?? [:])
        case .codexTOML:
            []
        }
    }

    private static func merge(
        servers: [MCPServer],
        into root: [String: Any],
        format: MCPServerConfigFormat
    ) -> [String: Any] {
        var root = root
        switch format {
        case .standardJSON:
            root["mcpServers"] = Dictionary(uniqueKeysWithValues: servers.map { ($0.name, standardObject($0)) })
        case .openCodeJSON:
            root["$schema"] = root["$schema"] ?? "https://opencode.ai/config.json"
            root["mcp"] = Dictionary(uniqueKeysWithValues: servers.map { ($0.name, openCodeObject($0)) })
        case .codexTOML:
            break
        }
        return root
    }

    private static func standardObject(_ server: MCPServer) -> [String: Any] {
        var object = [String: Any]()
        if server.transport == .remote {
            object["url"] = server.url
            object["headers"] = server.headers.isEmpty ? nil : server.headers
        } else {
            object["command"] = server.command
            object["args"] = server.arguments
            object["env"] = server.environment.isEmpty ? nil : server.environment
            object["cwd"] = nonEmpty(server.cwd)
        }
        object["type"] = nonEmpty(server.type)
        object["enabled"] = server.enabled ? nil : false
        object["directTools"] = server.directTools ? true : nil
        object["bearer_token_env_var"] = nonEmpty(server.bearerTokenEnvVar)
        return object
    }

    private static func openCodeObject(_ server: MCPServer) -> [String: Any] {
        var object = [String: Any]()
        object["type"] = server.transport == .remote ? "remote" : "local"
        object["enabled"] = server.enabled
        if server.transport == .remote {
            object["url"] = server.url
            object["headers"] = server.headers.isEmpty ? nil : server.headers
        } else {
            object["command"] = [server.command] + server.arguments
            object["environment"] = server.environment.isEmpty ? nil : server.environment
            object["cwd"] = nonEmpty(server.cwd)
        }
        return object
    }

}

extension MCPJSONConfigCodec {
    static func standardServers(from values: [String: Any]) -> [MCPServer] {
        values.keys.sorted().compactMap { name in
            standardServer(name: name, value: values[name])
        }
    }

    static func standardServer(name: String, value: Any?) -> MCPServer? {
        guard let value = value as? [String: Any] else { return nil }
        let command = value["command"] as? String ?? ""
        let url = value["url"] as? String ?? value["endpoint"] as? String ?? ""
        let type = value["type"] as? String ?? value["transport"] as? String
        return MCPServer(
            name: name,
            transport: transport(type: type, url: url),
            command: command,
            arguments: value["args"] as? [String] ?? [],
            url: url,
            environment: stringMap(value["env"]),
            headers: stringMap(value["headers"]),
            enabled: value["enabled"] as? Bool ?? true,
            directTools: value["directTools"] as? Bool ?? false,
            type: type,
            cwd: value["cwd"] as? String,
            bearerTokenEnvVar: value["bearer_token_env_var"] as? String,
            pluginID: nil,
            sourceLocationID: nil,
            sourceTitle: nil,
            authSummary: authSummary(value),
            toolNames: [],
            runtimeSummary: nil
        )
    }

    static func openCodeServers(from values: [String: Any]) -> [MCPServer] {
        values.keys.sorted().compactMap { name in
            guard let value = values[name] as? [String: Any] else { return nil }
            let commandParts = value["command"] as? [String] ?? []
            let url = value["url"] as? String ?? ""
            return MCPServer(
                name: name,
                transport: transport(type: value["type"] as? String, url: url),
                command: commandParts.first ?? "",
                arguments: Array(commandParts.dropFirst()),
                url: url,
                environment: stringMap(value["environment"]),
                headers: stringMap(value["headers"]),
                enabled: value["enabled"] as? Bool ?? true,
                directTools: false,
                type: value["type"] as? String ?? (url.isEmpty ? "local" : "remote"),
                cwd: value["cwd"] as? String,
                bearerTokenEnvVar: value["bearer_token_env_var"] as? String,
                pluginID: nil,
                sourceLocationID: nil,
                sourceTitle: nil,
                authSummary: authSummary(value),
                toolNames: [],
                runtimeSummary: nil
            )
        }
    }

    static func stringMap(_ value: Any?) -> [String: String] {
        guard let values = value as? [String: Any] else { return [:] }
        return values.reduce(into: [String: String]()) { result, item in
            guard let value = item.value as? String else { return }
            result[item.key] = value
        }
    }

    private static func transport(type: String?, url: String) -> MCPServerTransport {
        if let type = type?.lowercased(), ["http", "sse", "streamable-http", "remote"].contains(type) { return .remote }
        return url.isEmpty ? .stdio : .remote
    }

    private static func authSummary(_ value: [String: Any]) -> String? {
        if value["bearer_token_env_var"] != nil { return "Bearer token" }
        if value["headers"] != nil { return "Headers" }
        return nil
    }
}

private func nonEmpty(_ value: String?) -> String? {
    guard let value, !value.isEmpty else { return nil }
    return value
}
