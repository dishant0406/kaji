import Foundation

@MainActor
enum NotificationEventNormalizer {
    static func normalize(
        notification: KajiNotification,
        appState: AppState?,
        worktreeStore: WorktreeStore?
    ) -> NotificationOutboundEvent {
        let source = normalizeSource(notification.source)
        let kind = normalizeKind(source: source, title: notification.title, body: notification.body)
        let project = projectName(for: notification, appState: appState) ?? lastPathComponent(notification.worktreePath)
        let worktree = worktreeName(for: notification, worktreeStore: worktreeStore) ?? lastPathComponent(notification.worktreePath)
        let title = normalizedTitle(
            source: source,
            title: notification.title,
            project: project
        )
        return NotificationOutboundEvent(
            source: source,
            kind: kind,
            title: title,
            body: notification.body,
            project: project,
            worktree: worktree,
            timestamp: notification.timestamp
        )
    }

    private static func normalizeSource(_ source: KajiNotification.Source) -> NotificationRouteSource {
        switch source {
        case .osc:
            .terminal
        case let .aiProvider(id):
            AgentProviderCatalog.routeSource(for: id) ?? .custom
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
            || text.contains("permission")
        {
            return .attention
        }
        if isCodingAgent(source) {
            return .completed
        }
        return .info
    }

    private static func projectName(for notification: KajiNotification, appState: AppState?) -> String? {
        guard let appState else { return nil }
        return appState.activeProjectID == notification.projectID ? lastPathComponent(notification.worktreePath) : nil
    }

    private static func worktreeName(for notification: KajiNotification, worktreeStore: WorktreeStore?) -> String? {
        worktreeStore?.worktree(projectID: notification.projectID, worktreeID: notification.worktreeID)?.name
    }

    private static func lastPathComponent(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    private static func normalizedTitle(
        source: NotificationRouteSource,
        title: String,
        project: String
    ) -> String {
        guard isCodingAgent(source),
              !project.isEmpty,
              !title.contains(project)
        else {
            return title
        }

        return title + " · " + project
    }

    private static func isCodingAgent(_ source: NotificationRouteSource) -> Bool {
        AgentProviderCatalog.isAgentRouteSource(source)
    }
}
