import Foundation

struct GitCommitMessageAgentRequest: Hashable {
    let projectName: String
    let repoPath: String
    let inventory: GitCommitInventory
    let nativeDraft: String
    let settings: GitCommitMessageSettingsSnapshot
}
