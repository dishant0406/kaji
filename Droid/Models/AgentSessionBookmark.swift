import Foundation

struct AgentSessionBookmark: Identifiable, Codable, Hashable {
    let id: UUID
    let providerID: String
    let providerTitle: String
    let sessionID: String
    let title: String
    let folderName: String
    let projectID: UUID
    let worktreeID: UUID
    let worktreePath: String?
    let createdAt: Date
    var updatedAt: Date
}

struct AgentSessionBookmarkCandidate: Identifiable, Hashable {
    let paneID: UUID
    let provider: AskProvider
    let sessionID: String
    let title: String
    let projectID: UUID
    let worktreeID: UUID
    let worktreePath: String?
    let areaID: UUID
    let tabID: UUID

    var id: UUID { paneID }
}
