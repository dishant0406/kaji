import Foundation

struct AskDispatchRequest {
    let prompt: String
    let project: Project
    let worktree: Worktree
    let provider: AskProvider
    let sessionMode: AskSessionMode
    let session: AskSessionOption?
    let history: AskHistoryOption?
    let skill: AskSkillOption?
}
