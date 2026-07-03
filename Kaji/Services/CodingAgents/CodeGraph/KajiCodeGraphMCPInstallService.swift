import Foundation

struct KajiCodeGraphMCPInstallOutcome: Equatable {
    let agentID: String
    let installed: Bool
    let detail: String
}

enum KajiCodeGraphMCPInstallService {
    static let serverName = "kaji-codegraph"
    static let supportedAgentIDs = ["codex", "claude", "opencode", "pi"]

    static func installAll(homeDirectory: String = NSHomeDirectory(), projectPath: String? = nil) -> [KajiCodeGraphMCPInstallOutcome] {
        do {
            let command = try KajiCodeGraphMCPBinaryInstaller.install(homeDirectory: homeDirectory)
            return supportedAgentIDs.map { install(agentID: $0, command: command, homeDirectory: homeDirectory, projectPath: projectPath) }
        } catch {
            return supportedAgentIDs.map { .init(agentID: $0, installed: false, detail: error.localizedDescription) }
        }
    }

    static func uninstallAll(homeDirectory: String = NSHomeDirectory(), projectPath: String? = nil) -> [KajiCodeGraphMCPInstallOutcome] {
        let outcomes = supportedAgentIDs.map { uninstall(agentID: $0, homeDirectory: homeDirectory, projectPath: projectPath) }
        do {
            try KajiCodeGraphMCPBinaryInstaller.remove(homeDirectory: homeDirectory)
            return outcomes
        } catch {
            return outcomes + [.init(agentID: serverName, installed: false, detail: error.localizedDescription)]
        }
    }

    static func installedAgentIDs(homeDirectory: String = NSHomeDirectory(), projectPath: String? = nil) -> [String] {
        guard KajiCodeGraphMCPBinaryInstaller.isInstalled(homeDirectory: homeDirectory) else { return [] }
        return supportedAgentIDs.filter { agentID in
            userLocations(agentID: agentID, homeDirectory: homeDirectory, projectPath: projectPath).contains { location in
                guard let servers = try? MCPServerConfigProviderDefault.read(location: location) else { return false }
                return servers.contains { $0.name == serverName && $0.enabled }
            }
        }
    }

    static func isInstalled(homeDirectory: String = NSHomeDirectory(), projectPath: String? = nil) -> Bool {
        !installedAgentIDs(homeDirectory: homeDirectory, projectPath: projectPath).isEmpty
    }

    private static func install(
        agentID: String,
        command: URL,
        homeDirectory: String,
        projectPath: String?
    ) -> KajiCodeGraphMCPInstallOutcome {
        guard let location = userLocations(agentID: agentID, homeDirectory: homeDirectory, projectPath: projectPath).first else {
            return .init(agentID: agentID, installed: false, detail: "No writable MCP config location")
        }
        do {
            var servers = try MCPServerConfigProviderDefault.read(location: location).filter { $0.name != serverName }
            servers.append(server(command: command.path))
            try MCPServerConfigProviderDefault.write(servers, location: location)
            return .init(agentID: agentID, installed: true, detail: location.url.path)
        } catch {
            return .init(agentID: agentID, installed: false, detail: error.localizedDescription)
        }
    }

    private static func uninstall(agentID: String, homeDirectory: String, projectPath: String?) -> KajiCodeGraphMCPInstallOutcome {
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
        return provider.mcpServerLocations(projectPath: projectPath, homeDirectory: homeDirectory).filter { location in
            location.scope == .user && !location.url.lastPathComponent.contains("cache")
        }
    }

    private static func server(command: String) -> MCPServer {
        var server = MCPServer.empty()
        server.name = serverName
        server.transport = .stdio
        server.command = command
        server.arguments = []
        server.environment = [:]
        server.enabled = true
        server.directTools = false
        return server
    }
}
