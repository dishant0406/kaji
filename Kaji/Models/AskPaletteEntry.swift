import Foundation

enum AskPaletteAction: Hashable {
    case command(AskSlashCommand)
    case project(Project)
    case worktree(Worktree)
    case provider(AskProvider)
    case sessionMode(AskSessionMode)
    case session(AskSessionOption)
    case bookmarkSession(AgentSessionBookmarkCandidate, selected: Bool)
    case saveSelectedBookmarks
    case bookmarkLookupLoading
    case bookmarkFolder(String)
    case createBookmarkFolder(String)
    case savedBookmark(AgentSessionBookmark)
    case bookmarkFolderFilter(String)
    case history(AskHistoryOption)
    case skill(AskSkillOption)
    case taskRecipe(AskTaskRecipe)
    case openTaskForm
    case editTaskRecipe(AskTaskRecipe)
    case deleteTaskRecipe(AskTaskRecipe)
    case mention(AskMentionOption)
    case directory(AskDirectoryOption)
    case diffFile(DiffPaletteFile)
    case openDiffSummary(projectID: UUID, worktreeID: UUID, worktreePath: String)
    case gitCommand(GitCommandRequest)
    case gitBranch(name: String, isCurrent: Bool)
    case gitSwitchBranch(String)
    case gitCheckoutBranch(String)
    case attach
    case runScript(KajiKitScript)
    case openScriptForm(KajiKitScript?)
    case deleteScript(KajiKitScript)
    case toggleSleepPrevention
    case toggleBatteryLidCloseSleepPrevention
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
        case let .bookmarkSession(candidate, selected):
            "bookmark:\(candidate.id.uuidString):\(selected)"
        case .saveSelectedBookmarks:
            "save-selected-bookmarks"
        case .bookmarkLookupLoading:
            "bookmark-lookup-loading"
        case let .bookmarkFolder(folder):
            "bookmark-folder:\(folder)"
        case let .createBookmarkFolder(folder):
            "create-bookmark-folder:\(folder)"
        case let .savedBookmark(bookmark):
            "saved-bookmark:\(bookmark.id.uuidString)"
        case let .bookmarkFolderFilter(folder):
            "bookmark-folder-filter:\(folder)"
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
        case let .diffFile(file):
            "diff-file:\(file.id)"
        case let .openDiffSummary(projectID, worktreeID, worktreePath):
            "diff-summary:\(projectID.uuidString):\(worktreeID.uuidString):\(worktreePath)"
        case let .gitCommand(request):
            "git-command:\(request.id)"
        case let .gitBranch(name, isCurrent):
            "git-branch:\(name):\(isCurrent)"
        case let .gitSwitchBranch(branch):
            "git-switch:\(branch)"
        case let .gitCheckoutBranch(branch):
            "git-checkout:\(branch)"
        case .attach:
            "attach"
        case let .runScript(script):
            "run-script:\(script.id.uuidString)"
        case let .openScriptForm(script):
            "script-form:\(script?.id.uuidString ?? "new")"
        case let .deleteScript(script):
            "delete-script:\(script.id.uuidString)"
        case .toggleSleepPrevention:
            "toggle-sleep-prevention"
        case .toggleBatteryLidCloseSleepPrevention:
            "toggle-battery-lid-close-sleep-prevention"
        case let .launchProvider(provider):
            "launch:\(provider.rawValue)"
        case .submit:
            "submit"
        }
    }
}
