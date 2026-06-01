import Foundation

enum KajiAgentSessionDirectory {
    static func path(for scope: KajiAgentScope) -> String {
        KajiFileStorage.appSupportDirectory()
            .appendingPathComponent("AgentRuntime", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(scope.projectID.uuidString, isDirectory: true)
            .appendingPathComponent("worktrees", isDirectory: true)
            .appendingPathComponent(scope.worktreeID.uuidString, isDirectory: true)
            .path
    }
}
