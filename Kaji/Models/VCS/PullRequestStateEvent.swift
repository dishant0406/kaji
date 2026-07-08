import Foundation

struct PullRequestStateEvent {
    let repoPath: String
    let branch: String
    let headSha: String?
    let info: GitRepositoryService.PRInfo?
    let account: GitHubAccount?
}
