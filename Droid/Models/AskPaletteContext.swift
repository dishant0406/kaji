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
    let taskRecipes: [AskTaskRecipe]
    let scripts: [DroidKitScript]
    let mentionOptions: [AskMentionOption]
    let directoryOptions: [AskDirectoryOption]
    let projectName: String
    let worktreeName: String
    let sleepPreventionIsEnabled: Bool
    let systemSleepAssertionStatus: SystemSleepAssertionStatus
    let batteryLidCloseSleepIsEnabled: Bool
    let batteryLidCloseSleepStatus: SystemSleepAssertionStatus

    init(
        fieldText: String,
        prompt: String,
        projects: [Project],
        worktrees: [Worktree],
        provider: AskProvider,
        sessionMode: AskSessionMode,
        sessions: [AskSessionOption],
        historyOptions: [AskHistoryOption],
        skillOptions: [AskSkillOption],
        taskRecipes: [AskTaskRecipe] = AskTaskRecipe.builtIns,
        scripts: [DroidKitScript] = [],
        mentionOptions: [AskMentionOption] = [],
        directoryOptions: [AskDirectoryOption] = [],
        projectName: String,
        worktreeName: String,
        sleepPreventionIsEnabled: Bool = false,
        systemSleepAssertionStatus: SystemSleepAssertionStatus = .inactive,
        batteryLidCloseSleepIsEnabled: Bool = false,
        batteryLidCloseSleepStatus: SystemSleepAssertionStatus = .inactive
    ) {
        self.fieldText = fieldText
        self.prompt = prompt
        self.projects = projects
        self.worktrees = worktrees
        self.provider = provider
        self.sessionMode = sessionMode
        self.sessions = sessions
        self.historyOptions = historyOptions
        self.skillOptions = skillOptions
        self.taskRecipes = taskRecipes
        self.scripts = scripts
        self.mentionOptions = mentionOptions
        self.directoryOptions = directoryOptions
        self.projectName = projectName
        self.worktreeName = worktreeName
        self.sleepPreventionIsEnabled = sleepPreventionIsEnabled
        self.systemSleepAssertionStatus = systemSleepAssertionStatus
        self.batteryLidCloseSleepIsEnabled = batteryLidCloseSleepIsEnabled
        self.batteryLidCloseSleepStatus = batteryLidCloseSleepStatus
    }
}
