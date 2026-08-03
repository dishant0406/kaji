import Foundation

struct KajiCodeMCPInstallOutcome: Equatable {
    let agentID: String
    let installed: Bool
    let detail: String
}

enum KajiCodeMCPInstallService {
    static let serverName = "kajicode"
    static let supportedAgentIDs = ["codex", "claude", "opencode", "pi"]

    static func installAll(
        homeDirectory: String = NSHomeDirectory(),
        projectPath: String? = nil,
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> [KajiCodeMCPInstallOutcome] {
        guard let resolution = KajiCodeRuntimeLocator.resolve(env: env, homeDirectory: homeDirectory, fileManager: fileManager) else {
            return supportedAgentIDs.map { .init(agentID: $0, installed: false, detail: "KajiCode binary not found") }
        }
        let environment = ShellExecutionEnvironmentResolver.resolve(env: env, homeDirectory: homeDirectory, fileManager: fileManager)
        return installAll(
            binaryURL: resolution.binaryURL,
            homeDirectory: homeDirectory,
            projectPath: projectPath,
            environment: ShellExecutionEnvironmentResolver.mcpEnvironment(from: environment)
        )
    }

    static func installAll(
        binaryURL: URL,
        homeDirectory: String = NSHomeDirectory(),
        projectPath: String? = nil,
        environment: [String: String] = [:]
    ) -> [KajiCodeMCPInstallOutcome] {
        supportedAgentIDs.map {
            install(agentID: $0, command: binaryURL, homeDirectory: homeDirectory, projectPath: projectPath, environment: environment)
        }
    }

    static func uninstallAll(homeDirectory: String = NSHomeDirectory(), projectPath: String? = nil) -> [KajiCodeMCPInstallOutcome] {
        supportedAgentIDs.map { uninstall(agentID: $0, homeDirectory: homeDirectory, projectPath: projectPath) }
    }

    static func installedAgentIDs(
        homeDirectory: String = NSHomeDirectory(),
        projectPath: String? = nil,
        fileManager: FileManager = .default
    ) -> [String] {
        supportedAgentIDs.filter { agentID in
            userLocations(agentID: agentID, homeDirectory: homeDirectory, projectPath: projectPath).contains { location in
                guard let servers = try? MCPServerConfigProviderDefault.read(location: location) else { return false }
                return servers.contains { server in
                    server.name == serverName && server.enabled && fileManager.isExecutableFile(atPath: server.command)
                }
            }
        }
    }

    private static func install(
        agentID: String,
        command: URL,
        homeDirectory: String,
        projectPath: String?,
        environment: [String: String]
    ) -> KajiCodeMCPInstallOutcome {
        guard let location = userLocations(agentID: agentID, homeDirectory: homeDirectory, projectPath: projectPath).first else {
            return .init(agentID: agentID, installed: false, detail: "No writable MCP config location")
        }
        do {
            var servers = try MCPServerConfigProviderDefault.read(location: location).filter { $0.name != serverName }
            servers.append(server(command: command.path, environment: environment))
            try MCPServerConfigProviderDefault.write(servers, location: location)
            return .init(agentID: agentID, installed: true, detail: location.url.path)
        } catch {
            return .init(agentID: agentID, installed: false, detail: error.localizedDescription)
        }
    }

    private static func uninstall(agentID: String, homeDirectory: String, projectPath: String?) -> KajiCodeMCPInstallOutcome {
        let locations = userLocations(agentID: agentID, homeDirectory: homeDirectory, projectPath: projectPath)
        guard !locations.isEmpty else { return .init(agentID: agentID, installed: false, detail: "No MCP config location") }
        do {
            for location in locations {
                let servers = try MCPServerConfigProviderDefault.read(location: location).filter { $0.name != serverName }
                try MCPServerConfigProviderDefault.write(servers, location: location)
            }
            return .init(agentID: agentID, installed: false, detail: "Removed")
        } catch {
            return .init(agentID: agentID, installed: true, detail: error.localizedDescription)
        }
    }

    private static func userLocations(agentID: String, homeDirectory: String, projectPath: String?) -> [MCPServerConfigLocation] {
        guard let provider = CodingAgentRegistry.shared.agent(id: agentID)?.mcpServerConfigProvider else { return [] }
        return provider.mcpServerLocations(projectPath: projectPath, homeDirectory: homeDirectory).filter { $0.scope == .user }
    }

    private static func server(command: String, environment: [String: String]) -> MCPServer {
        var server = MCPServer.empty()
        server.name = serverName
        server.transport = .stdio
        server.command = command
        server.arguments = ["serve", "--mcp"]
        server.environment = environment
        server.enabled = true
        return server
    }
}
