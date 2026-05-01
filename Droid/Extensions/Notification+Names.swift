import Foundation

extension Notification.Name {
    static let renameActiveTab = Notification.Name("DroidRenameActiveTab")
    static let toggleThemePicker = Notification.Name("DroidToggleThemePicker")
    static let toggleSettings = Notification.Name("DroidToggleSettings")
    static let dismissSettings = Notification.Name("DroidDismissSettings")
    static let themeDidChange = Notification.Name("DroidThemeDidChange")
    static let findInTerminal = Notification.Name("DroidFindInTerminal")
    static let toggleAttachedVCS = Notification.Name("DroidToggleAttachedVCS")
    static let toggleFileTree = Notification.Name("DroidToggleFileTree")
    static let quickOpen = Notification.Name("DroidQuickOpen")
    static let ask = Notification.Name("DroidAsk")
    static let agentCommandCenter = Notification.Name("DroidAgentCommandCenter")
    static let switchWorktree = Notification.Name("DroidSwitchWorktree")
    static let saveActiveEditor = Notification.Name("DroidSaveActiveEditor")
    static let windowFullScreenDidChange = Notification.Name("DroidWindowFullScreenDidChange")
    static let toggleSidebar = Notification.Name("DroidToggleSidebar")
    static let toggleNotificationPanel = Notification.Name("DroidToggleNotificationPanel")
    static let toggleAIUsage = Notification.Name("DroidToggleAIUsage")
    static let vcsRepoDidChange = Notification.Name("DroidVCSRepoDidChange")
    static let requestCreateWorktreeModal = Notification.Name("DroidRequestCreateWorktreeModal")
    static let requestCreateThemeModal = Notification.Name("DroidRequestCreateThemeModal")
}
