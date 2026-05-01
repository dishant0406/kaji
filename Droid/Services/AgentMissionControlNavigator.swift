import Foundation

@MainActor
enum AgentMissionControlNavigator {
    static func navigate(
        to item: AgentMissionControlItem,
        appState: AppState,
        worktreeStore: WorktreeStore,
        notificationStore: NotificationStore
    ) {
        if let notificationID = item.notificationID,
           let notification = notificationStore.notifications.first(where: { $0.id == notificationID })
        {
            NotificationNavigator.navigate(to: notification, appState: appState, notificationStore: notificationStore)
            return
        }
        guard let paneID = item.paneID,
              let context = NotificationNavigator.resolveContext(
                  for: paneID,
                  appState: appState,
                  worktreeStore: worktreeStore
              )
        else { return }
        appState.dispatch(.selectProject(
            projectID: context.projectID,
            worktreeID: context.worktreeID,
            worktreePath: context.worktreePath
        ))
        appState.dispatch(.focusArea(projectID: context.projectID, areaID: context.areaID))
        appState.dispatch(.selectTab(projectID: context.projectID, areaID: context.areaID, tabID: context.tabID))
    }
}
