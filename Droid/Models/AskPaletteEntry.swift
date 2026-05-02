import Foundation

enum AskPaletteAction: Hashable {
    case command(AskSlashCommand)
    case project(Project)
    case worktree(Worktree)
    case provider(AskProvider)
    case sessionMode(AskSessionMode)
    case session(AskSessionOption)
    case history(AskHistoryOption)
    case skill(AskSkillOption)
    case taskRecipe(AskTaskRecipe)
    case openTaskForm
    case editTaskRecipe(AskTaskRecipe)
    case deleteTaskRecipe(AskTaskRecipe)
    case mention(AskMentionOption)
    case directory(AskDirectoryOption)
    case attach
    case launchProvider(AskProvider)
    case submit
}

struct AskPaletteEntry: Identifiable, Hashable {
    let action: AskPaletteAction
    let title: String
    let detail: String
    let annotation: String?

    var id: String {
        switch action {
        case let .command(command):
            "command:\(command.rawValue)"
        case let .project(project):
            "project:\(project.id.uuidString)"
        case let .worktree(worktree):
            "worktree:\(worktree.id.uuidString)"
        case let .provider(provider):
            "provider:\(provider.rawValue)"
        case let .sessionMode(mode):
            "session-mode:\(mode.rawValue)"
        case let .session(session):
            "session:\(session.id.uuidString)"
        case let .history(history):
            "history:\(history.provider.rawValue):\(history.sessionID)"
        case let .skill(skill):
            "skill:\(skill.name):\(skill.path)"
        case let .taskRecipe(recipe):
            "task:\(recipe.id)"
        case .openTaskForm:
            "task-form"
        case let .editTaskRecipe(recipe):
            "edit-task:\(recipe.id)"
        case let .deleteTaskRecipe(recipe):
            "delete-task:\(recipe.id)"
        case let .mention(option):
            "mention:\(option.id)"
        case let .directory(option):
            "directory:\(option.path)"
        case .attach:
            "attach"
        case let .launchProvider(provider):
            "launch:\(provider.rawValue)"
        case .submit:
            "submit"
        }
    }
}
