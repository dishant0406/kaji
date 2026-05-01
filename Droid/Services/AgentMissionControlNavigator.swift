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
        NotificationNavigator.navigate(to: context, appState: appState)
    }
}
