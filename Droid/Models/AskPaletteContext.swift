import Foundation

struct AskPaletteContext {
    let fieldText: String
    let prompt: String
    let projects: [Project]
    let worktrees: [Worktree]
    let provider: AskProvider
    let sessionMode: AskSessionMode
    let sessions: [AskSessionOption]
    let historyOptions: [AskHistoryOption]
    let skillOptions: [AskSkillOption]
    let projectName: String
    let worktreeName: String
}
