import Foundation

enum MCPServerTransport: String, CaseIterable, Identifiable, Codable {
    case stdio
    case remote
    case plugin

    var id: String { rawValue }
    var title: String {
        switch self {
        case .stdio: "Stdio"
        case .remote: "Remote"
        case .plugin: "Plugin"
        }
    }
}

enum MCPServerConfigFormat: String, Codable {
    case standardJSON
    case openCodeJSON
    case codexTOML
}

enum MCPServerConfigScope: String, Codable {
    case user
    case project

    var title: String {
        switch self {
        case .user: "User"
        case .project: "Project"
        }
    }
}

struct MCPServerConfigLocation: Identifiable, Hashable {
    let id: String
    let agentID: String
    let title: String
    let scope: MCPServerConfigScope
    let url: URL
    let format: MCPServerConfigFormat
}

struct MCPServer: Identifiable, Equatable {
    var id: String { name }
    var name: String
    var transport: MCPServerTransport
    var command: String
    var arguments: [String]
    var url: String
    var environment: [String: String]
    var headers: [String: String]
    var enabled: Bool
    var directTools: Bool
    var type: String?
    var cwd: String?
    var bearerTokenEnvVar: String?
    var pluginID: String?
    var sourceLocationID: String?
    var sourceTitle: String?
    var authSummary: String?
    var toolNames: [String]
    var runtimeSummary: String?
}

extension MCPServer {
    static func empty() -> MCPServer {
        MCPServer(
            name: "",
            transport: .stdio,
            command: "",
            arguments: [],
            url: "",
            environment: [:],
            headers: [:],
            enabled: true,
            directTools: false,
            type: nil,
            cwd: nil,
            bearerTokenEnvVar: nil,
            pluginID: nil,
            sourceLocationID: nil,
            sourceTitle: nil,
            authSummary: nil,
            toolNames: [],
            runtimeSummary: nil
        )
    }
}

enum MCPAgentLoadState: Equatable {
    case idle
    case loading
    case enriching
    case loaded
    case failed(String)

    var isLoading: Bool {
        if case .loading = self { return true }
        if case .enriching = self { return true }
        return false
    }
}

struct MCPServerRuntimeRecord: Equatable, Sendable {
    var name: String
    var status: String?
    var authSummary: String?
    var url: String?
    var command: String?
    var toolNames: [String]
}

struct MCPServerStatus: Equatable {
    let title: String
    let detail: String
    let isHealthy: Bool
}

struct MCPAgentPanelState: Identifiable, Equatable {
    var id: String { agent.id }
    let agent: CodingAgentDefinition
    let locations: [MCPServerConfigLocation]
    var servers: [MCPServer]
    var errorMessage: String?
    var loadState: MCPAgentLoadState

    var primaryLocation: MCPServerConfigLocation? { locations.first }
}

enum MCPServerConfigError: LocalizedError {
    case unsupportedFormat
    case invalidJSON
    case invalidRoot
    case duplicateName
    case missingName
    case missingProjectPath

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: "Unsupported MCP configuration format."
        case .invalidJSON: "The MCP configuration JSON is invalid."
        case .invalidRoot: "The MCP configuration root must be an object."
        case .duplicateName: "A server with that name already exists."
        case .missingName: "Server name is required."
        case .missingProjectPath: "Project path is required for project MCP configuration."
        }
    }
}
