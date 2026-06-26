import Foundation

struct AskPaletteContext {
    let fieldText: String
    let prompt: String
    let projects: [Project]
    let worktrees: [Worktree]
    let provider: AskProvider
    let sessionMode: AskSessionMode
    let sessions: [AskSessionOption]
    let bookmarkCandidates: [AgentSessionBookmarkCandidate]
    let selectedBookmarkIDs: Set<UUID>
    let bookmarkLookupIsLoading: Bool
    let historyOptions: [AskHistoryOption]
    let skillOptions: [AskSkillOption]
    let taskRecipes: [AskTaskRecipe]
    let scripts: [KajiKitScript]
    let userCommandShortcuts: [UserCommandShortcut]
    let bookmarks: [AgentSessionBookmark]
    let bookmarkFolders: [String]
    let mentionOptions: [AskMentionOption]
    let directoryOptions: [AskDirectoryOption]
    let diffFiles: [DiffPaletteFile]
    let createPullRequestTarget: CreatePullRequestPaletteTarget?
    let gitBranches: [String]
    let currentGitBranch: String?
    let isLoadingGitBranches: Bool
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
        bookmarkCandidates: [AgentSessionBookmarkCandidate] = [],
        selectedBookmarkIDs: Set<UUID> = [],
        bookmarkLookupIsLoading: Bool = false,
        historyOptions: [AskHistoryOption],
        skillOptions: [AskSkillOption],
        taskRecipes: [AskTaskRecipe] = AskTaskRecipe.builtIns,
        scripts: [KajiKitScript] = [],
        userCommandShortcuts: [UserCommandShortcut] = [],
        bookmarks: [AgentSessionBookmark] = [],
        bookmarkFolders: [String] = [],
        mentionOptions: [AskMentionOption] = [],
        directoryOptions: [AskDirectoryOption] = [],
        diffFiles: [DiffPaletteFile] = [],
        createPullRequestTarget: CreatePullRequestPaletteTarget? = nil,
        gitBranches: [String] = [],
        currentGitBranch: String? = nil,
        isLoadingGitBranches: Bool = false,
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
        self.bookmarkCandidates = bookmarkCandidates
        self.selectedBookmarkIDs = selectedBookmarkIDs
        self.bookmarkLookupIsLoading = bookmarkLookupIsLoading
        self.historyOptions = historyOptions
        self.skillOptions = skillOptions
        self.taskRecipes = taskRecipes
        self.scripts = scripts
        self.userCommandShortcuts = userCommandShortcuts
        self.bookmarks = bookmarks
        self.bookmarkFolders = bookmarkFolders
        self.mentionOptions = mentionOptions
        self.directoryOptions = directoryOptions
        self.diffFiles = diffFiles
        self.createPullRequestTarget = createPullRequestTarget
        self.gitBranches = gitBranches
        self.currentGitBranch = currentGitBranch
        self.isLoadingGitBranches = isLoadingGitBranches
        self.projectName = projectName
        self.worktreeName = worktreeName
        self.sleepPreventionIsEnabled = sleepPreventionIsEnabled
        self.systemSleepAssertionStatus = systemSleepAssertionStatus
        self.batteryLidCloseSleepIsEnabled = batteryLidCloseSleepIsEnabled
        self.batteryLidCloseSleepStatus = batteryLidCloseSleepStatus
    }
}
