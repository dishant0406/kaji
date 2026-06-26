import Foundation

struct CreatePullRequestPaletteTarget: Hashable {
    let projectID: UUID
    let worktreeID: UUID
    let worktreePath: String
    let projectName: String
    let worktreeName: String
    let branchName: String
}
