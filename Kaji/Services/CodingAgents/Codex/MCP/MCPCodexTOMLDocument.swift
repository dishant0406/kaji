import Foundation

struct MCPCodexTOMLDocument {
    let content: String

    var servers: [String: MCPServer] {
        var servers = [String: MCPServer]()
        var activeName: String?
        var activeEnvName: String?
        var activePluginID: String?

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if let table = MCPCodexTOMLValue.tableName(from: line) {
                updateActiveTable(
                    table,
                    servers: &servers,
                    activeName: &activeName,
                    activeEnvName: &activeEnvName,
                    activePluginID: &activePluginID
                )
                continue
            }
            guard let assignment = MCPCodexTOMLValue.assignment(from: line) else { continue }
            if let activePluginID {
                applyPlugin(assignment: assignment, pluginID: activePluginID, servers: &servers)
            } else if let activeEnvName {
                var server = servers[activeEnvName] ?? MCPServer.emptyNamed(activeEnvName)
                server.environment[assignment.key] = MCPCodexTOMLValue.parseString(assignment.value)
                servers[activeEnvName] = server
            } else if let activeName {
                var server = servers[activeName] ?? MCPServer.emptyNamed(activeName)
                apply(assignment: assignment, to: &server)
                servers[activeName] = server
            }
        }
        return servers
    }

    func replacingServers(with servers: [MCPServer]) -> String {
        var lines = content.components(separatedBy: .newlines)
        while lines.last?.isEmpty == true {
            lines.removeLast()
        }
        for range in tableRanges(in: lines).reversed() {
            lines.removeSubrange(range)
        }
        if !lines.isEmpty { lines.append("") }
        lines.append(contentsOf: serialize(servers))
        return lines.joined(separator: "\n") + "\n"
    }

    private func updateActiveTable(
        _ table: String,
        servers: inout [String: MCPServer],
        activeName: inout String?,
        activeEnvName: inout String?,
        activePluginID: inout String?
    ) {
        activePluginID = nil
        if table.hasPrefix("mcp_servers."), table.hasSuffix(".env") {
            let name = String(table.dropFirst("mcp_servers.".count).dropLast(".env".count))
            activeName = nil
            activeEnvName = name
            servers[name] = servers[name] ?? MCPServer.emptyNamed(name)
            return
        }
        if table.hasPrefix("mcp_servers.") {
            let name = String(table.dropFirst("mcp_servers.".count))
            activeName = name
            activeEnvName = nil
            servers[name] = servers[name] ?? MCPServer.emptyNamed(name)
            return
        }
        if table.hasPrefix("plugins.") {
            let pluginID = String(table.dropFirst("plugins.".count)).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            activeName = nil
            activeEnvName = nil
            activePluginID = pluginID
            servers[pluginServerName(pluginID)] = servers[pluginServerName(pluginID)] ?? pluginServer(pluginID)
            return
        }
        activeName = nil
        activeEnvName = nil
    }

    private func apply(assignment: (key: String, value: String), to server: inout MCPServer) {
        switch assignment.key {
        case "command":
            server.command = MCPCodexTOMLValue.parseString(assignment.value)
        case "args":
            server.arguments = MCPCodexTOMLValue.parseArray(assignment.value)
        case "env":
            server.environment = MCPCodexTOMLValue.parseInlineTable(assignment.value)
        case "url":
            server.url = MCPCodexTOMLValue.parseString(assignment.value)
            server.transport = .remote
        case "enabled":
            server.enabled = MCPCodexTOMLValue.parseBool(assignment.value) ?? true
        case "cwd":
            server.cwd = MCPCodexTOMLValue.parseString(assignment.value)
        case "bearer_token_env_var":
            server.bearerTokenEnvVar = MCPCodexTOMLValue.parseString(assignment.value)
            server.authSummary = "Bearer token"
        default:
            break
        }
    }

    private func applyPlugin(assignment: (key: String, value: String), pluginID: String, servers: inout [String: MCPServer]) {
        guard assignment.key == "enabled" else { return }
        let name = pluginServerName(pluginID)
        var server = servers[name] ?? pluginServer(pluginID)
        server.enabled = MCPCodexTOMLValue.parseBool(assignment.value) ?? true
        servers[name] = server
    }

    private func tableRanges(in lines: [String]) -> [Range<Int>] {
        var ranges = [Range<Int>]()
        var index = 0
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard let table = MCPCodexTOMLValue.tableName(from: trimmed), table.hasPrefix("mcp_servers.") else {
                index += 1
                continue
            }
            let start = index
            index += 1
            while index < lines.count {
                let next = lines[index].trimmingCharacters(in: .whitespaces)
                if MCPCodexTOMLValue.tableName(from: next) != nil { break }
                index += 1
            }
            ranges.append(start ..< index)
        }
        return ranges
    }

    private func serialize(_ servers: [MCPServer]) -> [String] {
        servers.sorted { $0.name < $1.name }.flatMap { server -> [String] in
            guard server.transport != .plugin else { return [] }
            var lines = ["[mcp_servers.\(server.name)]"]
            if server.transport == .remote {
                lines.append("url = \"\(MCPCodexTOMLValue.escape(server.url))\"")
                if let bearer = server.bearerTokenEnvVar, !bearer.isEmpty {
                    lines.append("bearer_token_env_var = \"\(MCPCodexTOMLValue.escape(bearer))\"")
                }
            } else {
                lines.append("command = \"\(MCPCodexTOMLValue.escape(server.command))\"")
                let arguments = server.arguments.map { "\"\(MCPCodexTOMLValue.escape($0))\"" }.joined(separator: ", ")
                lines.append("args = [\(arguments)]")
                if !server.environment.isEmpty {
                    lines.append("env = { \(MCPCodexTOMLValue.inlineTable(server.environment)) }")
                }
                if let cwd = server.cwd, !cwd.isEmpty {
                    lines.append("cwd = \"\(MCPCodexTOMLValue.escape(cwd))\"")
                }
            }
            if !server.enabled { lines.append("enabled = false") }
            lines.append("")
            return lines
        }
    }

    private func pluginServerName(_ pluginID: String) -> String {
        pluginID.split(separator: "@").first.map(String.init) ?? pluginID
    }

    private func pluginServer(_ pluginID: String) -> MCPServer {
        var server = MCPServer.emptyNamed(pluginServerName(pluginID))
        server.transport = .plugin
        server.pluginID = pluginID
        return server
    }
}
