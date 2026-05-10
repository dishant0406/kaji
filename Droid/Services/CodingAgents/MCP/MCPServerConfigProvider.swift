import Foundation

protocol MCPServerConfigProvider: Sendable {
    func mcpServerLocations(projectPath: String?, homeDirectory: String) -> [MCPServerConfigLocation]
    func readMCPServers(location: MCPServerConfigLocation) throws -> [MCPServer]
    func writeMCPServers(_ servers: [MCPServer], location: MCPServerConfigLocation) throws
    func runtimeMCPServers(projectPath: String?, homeDirectory: String) -> [MCPServerRuntimeRecord]
}

extension MCPServerConfigProvider {
    func runtimeMCPServers(projectPath: String?, homeDirectory: String) -> [MCPServerRuntimeRecord] { [] }

    func readMCPServers(location: MCPServerConfigLocation) throws -> [MCPServer] {
        try MCPServerConfigProviderDefault.read(location: location)
    }

    func writeMCPServers(_ servers: [MCPServer], location: MCPServerConfigLocation) throws {
        try MCPServerConfigProviderDefault.write(servers, location: location)
    }
}

enum MCPServerConfigProviderDefault {
    static func read(location: MCPServerConfigLocation) throws -> [MCPServer] {
        guard FileManager.default.fileExists(atPath: location.url.path) else { return [] }
        switch location.format {
        case .standardJSON,
             .openCodeJSON:
            return try MCPJSONConfigCodec.read(data: Data(contentsOf: location.url), format: location.format)
        case .codexTOML:
            return try MCPCodexTOMLCodec.read(String(contentsOf: location.url, encoding: .utf8))
        }
    }

    static func write(_ servers: [MCPServer], location: MCPServerConfigLocation) throws {
        try FileManager.default.createDirectory(at: location.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existingData = try? Data(contentsOf: location.url)
        switch location.format {
        case .standardJSON,
             .openCodeJSON:
            let data = try MCPJSONConfigCodec.write(servers: servers, existingData: existingData, format: location.format)
            try data.write(to: location.url, options: .atomic)
        case .codexTOML:
            let content = MCPCodexTOMLCodec.write(
                servers: servers,
                existingContent: existingData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            )
            try content.data(using: .utf8)?.write(to: location.url, options: .atomic)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: location.url.path)
    }
}
