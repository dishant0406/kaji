import Foundation

@MainActor
enum NotificationDisplayTextResolver {
    static func title(
        for notification: KajiNotification,
        appState: AppState?,
        worktreeStore: WorktreeStore?
    ) -> String {
        NotificationEventNormalizer.normalize(
            notification: notification,
            appState: appState,
            worktreeStore: worktreeStore
        )
        .title
    }
}
