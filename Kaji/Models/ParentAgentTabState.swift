import Foundation

struct ParentAgentTabState {
    let id: UUID
    let projectID: UUID?
    let worktreeID: UUID?
    let projectPath: String
    let initialSessionPath: String?

    init(id: UUID = UUID(), projectID: UUID? = nil, worktreeID: UUID? = nil, projectPath: String, initialSessionPath: String? = nil) {
        self.id = id
        self.projectID = projectID
        self.worktreeID = worktreeID
        self.projectPath = projectPath
        self.initialSessionPath = initialSessionPath
    }

    var scope: KajiAgentScope? {
        guard let projectID, let worktreeID else { return nil }
        return KajiAgentScope(agentID: id, projectID: projectID, worktreeID: worktreeID, projectPath: projectPath)
    }
}

struct KajiAgentScope: Hashable {
    let agentID: UUID
    let projectID: UUID
    let worktreeID: UUID
    let projectPath: String
}
