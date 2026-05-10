import Foundation

enum MCPServerLocationFactory {
    static func user(
        agentID: String,
        title: String,
        homeDirectory: String,
        relativePath: String,
        format: MCPServerConfigFormat
    ) -> MCPServerConfigLocation {
        let url = URL(fileURLWithPath: homeDirectory).appendingPathComponent(relativePath)
        return MCPServerConfigLocation(
            id: "\(agentID):\(url.path)",
            agentID: agentID,
            title: title,
            scope: .user,
            url: url,
            format: format
        )
    }

    static func project(
        agentID: String,
        title: String,
        projectPath: String?,
        relativePath: String,
        format: MCPServerConfigFormat
    ) -> [MCPServerConfigLocation] {
        guard let projectPath, !projectPath.isEmpty else { return [] }
        let url = URL(fileURLWithPath: projectPath).appendingPathComponent(relativePath)
        return [MCPServerConfigLocation(
            id: "\(agentID):\(url.path)",
            agentID: agentID,
            title: title,
            scope: .project,
            url: url,
            format: format
        )]
    }
}
