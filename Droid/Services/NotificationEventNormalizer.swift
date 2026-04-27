import Foundation

@MainActor
enum NotificationEventNormalizer {
    static func normalize(
        notification: DroidNotification,
        appState: AppState?,
        worktreeStore: WorktreeStore?
    ) -> NotificationOutboundEvent {
        let source = normalizeSource(notification.source)
        let kind = normalizeKind(source: source, title: notification.title, body: notification.body)
        let project = projectName(for: notification, appState: appState) ?? lastPathComponent(notification.worktreePath)
        let worktree = worktreeName(for: notification, worktreeStore: worktreeStore) ?? lastPathComponent(notification.worktreePath)
        return NotificationOutboundEvent(
            source: source,
            kind: kind,
            title: notification.title,
            body: notification.body,
            project: project,
            worktree: worktree,
            timestamp: notification.timestamp
        )
    }

    private static func normalizeSource(_ source: DroidNotification.Source) -> NotificationRouteSource {
        switch source {
        case .osc:
            .terminal
        case let .aiProvider(id):
            switch id {
            case "codex": .codex
            case "claude": .claude
            case "opencode": .opencode
            default: .custom
            }
        case .socket:
            .custom
        }
    }

    private static func normalizeKind(
        source: NotificationRouteSource,
        title: String,
        body: String
    ) -> NotificationEventKind {
        let text = "\(title) \(body)".lowercased()
        if text.contains("error") || text.contains("failed") {
            return .error
        }
        if text.contains("attention")
            || text.contains("action required")
            || text.contains("input required")
            || text.contains("approval")
        {
            return .attention
        }
        if source == .codex || source == .claude || source == .opencode {
            return .completed
        }
        return .info
    }

    private static func projectName(for notification: DroidNotification, appState: AppState?) -> String? {
        guard let appState else { return nil }
        return appState.activeProjectID == notification.projectID ? lastPathComponent(notification.worktreePath) : nil
    }

    private static func worktreeName(for notification: DroidNotification, worktreeStore: WorktreeStore?) -> String? {
        worktreeStore?.worktree(projectID: notification.projectID, worktreeID: notification.worktreeID)?.name
    }

    private static func lastPathComponent(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}
