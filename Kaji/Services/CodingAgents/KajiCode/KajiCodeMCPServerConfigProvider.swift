import Foundation

struct KajiCodeMCPServerConfigProvider: MCPServerConfigProvider {
    func mcpServerLocations(projectPath: String?, homeDirectory: String) -> [MCPServerConfigLocation] {
        [
            MCPServerLocationFactory.user(
                agentID: "kajicode",
                title: "KajiCode user config.json",
                homeDirectory: homeDirectory,
                relativePath: ".config/kajicode/config.json",
                format: .standardJSON
            ),
        ] + MCPServerLocationFactory.project(
            agentID: "kajicode",
            title: "KajiCode project config.json",
            projectPath: projectPath,
            relativePath: ".kajicode/config.json",
            format: .standardJSON
        )
    }

    func readMCPServers(location: MCPServerConfigLocation) throws -> [MCPServer] {
        guard FileManager.default.fileExists(atPath: location.url.path) else { return [] }
        let data = try Data(contentsOf: location.url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MCPServerConfigError.invalidRoot
        }
        return serverObjects(from: root).keys.sorted().compactMap { name in
            server(name: name, value: serverObjects(from: root)[name])
        }
    }

    func writeMCPServers(_ servers: [MCPServer], location: MCPServerConfigLocation) throws {
        try FileManager.default.createDirectory(at: location.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var root = try rootObject(from: try? Data(contentsOf: location.url))
        var mcp = root["mcp"] as? [String: Any] ?? [:]
        mcp["servers"] = Dictionary(uniqueKeysWithValues: servers.map { ($0.name, serverObject($0)) })
        root["mcp"] = mcp
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: location.url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: location.url.path)
    }

    private func rootObject(from data: Data?) throws -> [String: Any] {
        guard let data, !data.isEmpty else { return [:] }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MCPServerConfigError.invalidRoot
        }
        return root
    }

    private func serverObjects(from root: [String: Any]) -> [String: Any] {
        guard let mcp = root["mcp"] as? [String: Any] else { return [:] }
        return mcp["servers"] as? [String: Any] ?? [:]
    }

    private func server(name: String, value: Any?) -> MCPServer? {
        guard let value = value as? [String: Any] else { return nil }
        let command = value["command"] as? String ?? ""
        let url = value["url"] as? String ?? ""
        let type = value["type"] as? String
        return MCPServer(
            name: name,
            transport: url.isEmpty ? .stdio : .remote,
            command: command,
            arguments: value["args"] as? [String] ?? [],
            url: url,
            environment: MCPJSONConfigCodec.stringMap(value["env"]),
            headers: MCPJSONConfigCodec.stringMap(value["headers"]),
            enabled: !(value["disabled"] as? Bool ?? false),
            directTools: false,
            type: type,
            cwd: nil,
            bearerTokenEnvVar: nil,
            pluginID: nil,
            sourceLocationID: nil,
            sourceTitle: nil,
            authSummary: value["auth"] as? String,
            toolNames: [],
            runtimeSummary: nil
        )
    }

    private func serverObject(_ server: MCPServer) -> [String: Any] {
        var object = [String: Any]()
        object["type"] = server.transport == .remote ? (server.type ?? "http") : "stdio"
        object["command"] = server.transport == .stdio ? server.command : nil
        object["args"] = server.transport == .stdio ? server.arguments : nil
        object["env"] = server.environment.isEmpty ? nil : server.environment
        object["url"] = server.transport == .remote ? server.url : nil
        object["headers"] = server.headers.isEmpty ? nil : server.headers
        object["disabled"] = server.enabled ? nil : true
        return object
    }
}
