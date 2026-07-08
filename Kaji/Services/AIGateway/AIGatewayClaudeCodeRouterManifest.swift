import Foundation

struct AIGatewayClaudeCodeRouterManifest: Codable, Equatable {
    let packageName: String
    let packageVersion: String
    let nodeVersion: String
    let installedAt: Date

    static func current(nodeVersion: String) -> AIGatewayClaudeCodeRouterManifest {
        AIGatewayClaudeCodeRouterManifest(
            packageName: AIGatewayClaudeCodeRouterPaths.packageName,
            packageVersion: AIGatewayClaudeCodeRouterPaths.packageVersion,
            nodeVersion: nodeVersion,
            installedAt: Date()
        )
    }

    var matchesCurrentPackage: Bool {
        packageName == AIGatewayClaudeCodeRouterPaths.packageName
            && packageVersion == AIGatewayClaudeCodeRouterPaths.packageVersion
    }
}
