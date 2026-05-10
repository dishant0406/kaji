import Foundation
import Observation
import os

private let mcpServerLogger = Logger(subsystem: "app.droid", category: "MCPServerConfigStore")

@MainActor
@Observable
final class MCPServerConfigStore {
    static let shared = MCPServerConfigStore()

    private(set) var panels: [MCPAgentPanelState] = []
    private(set) var isLoading = false

    @ObservationIgnored private let fileManager: FileManager
    @ObservationIgnored private let homeDirectory: String
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init(fileManager: FileManager = .default, homeDirectory: String = NSHomeDirectory()) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
    }

    func load(projectPath: String?) {
        loadTask?.cancel()
        let descriptors = panelDescriptors(projectPath: projectPath)
        panels = descriptors.map { descriptor in
            MCPAgentPanelState(
                agent: descriptor.agent,
                locations: descriptor.locations,
                servers: [],
                errorMessage: nil,
                loadState: .loading
            )
        }
        isLoading = true
        let scanHomeDirectory = homeDirectory
        loadTask = Task.detached(priority: .userInitiated) {
            for descriptor in descriptors {
                guard !Task.isCancelled else { return }
                let result = await Self.readPanel(descriptor: descriptor, projectPath: projectPath, homeDirectory: scanHomeDirectory)
                await MainActor.run { [weak self] in
                    self?.apply(result)
                }
            }
            await MainActor.run { [weak self] in
                self?.isLoading = false
            }
        }
    }

    func upsert(_ server: MCPServer, agentID: String, originalName: String?) {
        guard let index = panels.firstIndex(where: { $0.agent.id == agentID }) else { return }
        guard server.transport != .plugin else { return }
        do {
            var servers = panels[index].servers
            let normalized = try validated(server, existing: servers, originalName: originalName)
            if let originalName, let serverIndex = servers.firstIndex(where: { $0.name == originalName }) {
                servers[serverIndex] = normalized
            } else {
                servers.append(normalized)
            }
            let location = try writeLocation(for: normalized, panel: panels[index])
            try provider(for: panels[index]).writeMCPServers(
                servers.filter { $0.sourceLocationID == location.id || $0.sourceLocationID == nil },
                location: location
            )
            servers = try mergedServers(for: panels[index], replacing: servers, in: location)
            panels[index].servers = servers.sorted { $0.name < $1.name }
            panels[index].errorMessage = nil
        } catch {
            panels[index].errorMessage = error.localizedDescription
        }
    }

    func delete(serverName: String, agentID: String) {
        guard let index = panels.firstIndex(where: { $0.agent.id == agentID }) else { return }
        do {
            let server = panels[index].servers.first { $0.name == serverName }
            guard server?.transport != .plugin else { return }
            let location = try writeLocation(for: server, panel: panels[index])
            var servers = panels[index].servers.filter { $0.name != serverName }
            try provider(for: panels[index]).writeMCPServers(servers.filter { $0.sourceLocationID == location.id }, location: location)
            servers = try mergedServers(for: panels[index], replacing: servers, in: location)
            panels[index].servers = servers
            panels[index].errorMessage = nil
        } catch {
            panels[index].errorMessage = error.localizedDescription
        }
    }

    func toggle(serverName: String, agentID: String, enabled: Bool) {
        guard let index = panels.firstIndex(where: { $0.agent.id == agentID }),
              let serverIndex = panels[index].servers.firstIndex(where: { $0.name == serverName })
        else { return }
        guard panels[index].servers[serverIndex].transport != .plugin else { return }
        var server = panels[index].servers[serverIndex]
        server.enabled = enabled
        upsert(server, agentID: agentID, originalName: serverName)
    }

    func status(for server: MCPServer) -> MCPServerStatus {
        if !server.enabled {
            return MCPServerStatus(title: "Disabled", detail: "This server is saved but inactive.", isHealthy: false)
        }
        switch server.transport {
        case .plugin:
            return MCPServerStatus(title: "Runtime", detail: server.runtimeSummary ?? "Managed by agent plugin or runtime cache.", isHealthy: true)
        case .remote:
            guard URL(string: server.url) != nil else {
                return MCPServerStatus(title: "Invalid URL", detail: "Remote server URL is not valid.", isHealthy: false)
            }
            return MCPServerStatus(title: "Configured", detail: "Remote endpoint is ready for the agent to connect.", isHealthy: true)
        case .stdio:
            guard !server.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return MCPServerStatus(title: "Missing command", detail: "Add a command to launch this MCP server.", isHealthy: false)
            }
            let installed = isCommandAvailable(server.command)
            return MCPServerStatus(
                title: installed ? "Ready" : "Command not found",
                detail: installed ? "Launch command is available on this Mac." : "Install the executable or use an absolute path.",
                isHealthy: installed
            )
        }
    }

    private func isCommandAvailable(_ command: String) -> Bool {
        if command.hasPrefix("/") { return fileManager.isExecutableFile(atPath: command) }
        return AIProviderExecutableLocator.candidatePaths(
            for: command,
            env: ProcessInfo.processInfo.environment,
            homeDirectory: homeDirectory,
            fileManager: fileManager
        ).contains { fileManager.isExecutableFile(atPath: $0) }
    }

    private func panelDescriptors(projectPath: String?) -> [MCPAgentPanelDescriptor] {
        CodingAgentRegistry.shared.agents.compactMap { module in
            guard let provider = module.mcpServerConfigProvider else { return nil }
            let locations = provider.mcpServerLocations(projectPath: projectPath, homeDirectory: homeDirectory)
            guard !locations.isEmpty else { return nil }
            return MCPAgentPanelDescriptor(agent: module.definition, provider: provider, locations: locations)
        }
    }

    private func apply(_ result: MCPAgentPanelLoadResult) {
        guard let index = panels.firstIndex(where: { $0.agent.id == result.agentID }) else { return }
        panels[index].servers = result.servers.sorted { $0.name < $1.name }
        panels[index].errorMessage = result.errorMessage
        panels[index].loadState = result.errorMessage == nil ? .loaded : .failed(result.errorMessage ?? "Failed to load MCP servers")
    }

    private static func readPanel(
        descriptor: MCPAgentPanelDescriptor,
        projectPath: String?,
        homeDirectory: String
    ) async -> MCPAgentPanelLoadResult {
        var errorMessages = [String]()
        let servers = descriptor.locations.flatMap { location in
            do {
                return try descriptor.provider.readMCPServers(location: location).map { server in
                    var server = server
                    server.sourceLocationID = location.id
                    server.sourceTitle = location.title
                    return server
                }
            } catch {
                mcpServerLogger.error("Failed to read MCP config: \(error.localizedDescription)")
                errorMessages.append("\(location.title): \(error.localizedDescription)")
                return []
            }
        }
        let runtimeRecords = descriptor.provider.runtimeMCPServers(projectPath: projectPath, homeDirectory: homeDirectory)
        return MCPAgentPanelLoadResult(
            agentID: descriptor.agent.id,
            servers: merged(servers: servers, runtimeRecords: runtimeRecords),
            errorMessage: errorMessages.isEmpty ? nil : errorMessages.joined(separator: "\n")
        )
    }

    private static func merged(servers: [MCPServer], runtimeRecords: [MCPServerRuntimeRecord]) -> [MCPServer] {
        var servers = servers
        for record in runtimeRecords {
            if let index = servers.firstIndex(where: { $0.name == record.name }) {
                servers[index] = enriched(servers[index], with: record)
            } else {
                var server = MCPServer.empty()
                server.name = record.name
                server.transport = record.url == nil ? .plugin : .remote
                server.url = record.url ?? ""
                server.command = record.command ?? ""
                server.sourceTitle = "Runtime"
                server.runtimeSummary = record.status
                servers.append(enriched(server, with: record))
            }
        }
        return servers
    }

    private static func enriched(_ server: MCPServer, with record: MCPServerRuntimeRecord) -> MCPServer {
        var server = server
        server.authSummary = record.authSummary ?? server.authSummary
        server.toolNames = record.toolNames.isEmpty ? server.toolNames : record.toolNames
        server.runtimeSummary = record.status ?? server.runtimeSummary
        if server.url.isEmpty, let url = record.url { server.url = url }
        if server.command.isEmpty, let command = record.command { server.command = command }
        return server
    }

    private func writeLocation(for server: MCPServer?, panel: MCPAgentPanelState) throws -> MCPServerConfigLocation {
        if let id = server?.sourceLocationID, let location = panel.locations.first(where: { $0.id == id }) {
            return location
        }
        if let location = panel.primaryLocation { return location }
        throw MCPServerConfigError.missingProjectPath
    }

    private func provider(for panel: MCPAgentPanelState) throws -> MCPServerConfigProvider {
        guard let provider = CodingAgentRegistry.shared.agent(id: panel.agent.id)?.mcpServerConfigProvider else {
            throw MCPServerConfigError.unsupportedFormat
        }
        return provider
    }

    private func mergedServers(
        for panel: MCPAgentPanelState,
        replacing replacement: [MCPServer],
        in location: MCPServerConfigLocation
    ) throws -> [MCPServer] {
        let replacementNames = Set(replacement.filter { $0.sourceLocationID == location.id || $0.sourceLocationID == nil }.map(\.name))
        let untouched = panel.servers.filter { server in
            guard server.sourceLocationID != location.id else { return false }
            return !replacementNames.contains(server.name)
        }
        return untouched + replacement.map { server in
            var server = server
            server.sourceLocationID = server.sourceLocationID ?? location.id
            server.sourceTitle = server.sourceTitle ?? location.title
            return server
        }
    }

    private func validated(_ server: MCPServer, existing: [MCPServer], originalName: String?) throws -> MCPServer {
        var normalized = server
        normalized.name = server.name.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.command = server.command.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.url = server.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.name.isEmpty else { throw MCPServerConfigError.missingName }
        if existing.contains(where: { $0.name == normalized.name && $0.name != originalName }) {
            throw MCPServerConfigError.duplicateName
        }
        return normalized
    }
}

private struct MCPAgentPanelDescriptor: @unchecked Sendable {
    let agent: CodingAgentDefinition
    let provider: MCPServerConfigProvider
    let locations: [MCPServerConfigLocation]
}

private struct MCPAgentPanelLoadResult: @unchecked Sendable {
    let agentID: String
    let servers: [MCPServer]
    let errorMessage: String?
}
