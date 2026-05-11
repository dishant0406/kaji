import Foundation

enum MCPCodexTOMLCodec {
    static func read(_ content: String) -> [MCPServer] {
        MCPCodexTOMLDocument(content: content).servers.values.sorted { $0.name < $1.name }
    }

    static func write(servers: [MCPServer], existingContent: String) -> String {
        MCPCodexTOMLDocument(content: existingContent).replacingServers(with: servers)
    }
}

extension MCPServer {
    static func emptyNamed(_ name: String) -> MCPServer {
        var server = MCPServer.empty()
        server.name = name
        return server
    }
}
