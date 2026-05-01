import Foundation

@MainActor
enum AgentMissionControlSnapshotBuilder {
    static func items(
        activities: [AIActivityStore.Activity],
        notifications: [DroidNotification],
        projects: [Project],
        worktrees: [UUID: [Worktree]],
        now: Date = Date(),
        limit: Int = 30
    ) -> [AgentMissionControlItem] {
        let activeItems = activities.map { activity in
            item(activity: activity, projects: projects, worktrees: worktrees)
        }
        let activePaneIDs = Set(activeItems.compactMap(\.paneID))
        let recentItems: [AgentMissionControlItem] = Array(notifications.prefix(limit)).compactMap { notification in
            guard providerID(from: notification.source) != nil else { return nil }
            guard !activePaneIDs.contains(notification.paneID) else { return nil }
            return item(notification: notification, projects: projects, worktrees: worktrees, now: now)
        }
        return (activeItems + recentItems)
            .sorted { lhs, rhs in
                if lhs.status != rhs.status {
                    return priority(lhs.status) < priority(rhs.status)
                }
                return lhs.timestamp > rhs.timestamp
            }
            .prefix(limit)
            .map(\.self)
    }

    static func providerName(for providerID: String) -> String {
        switch providerID {
        case "codex":
            "Codex"
        case "claude":
            "Claude Code"
        case "opencode":
            "OpenCode"
        default:
            providerID.isEmpty ? "Agent" : providerID.capitalized
        }
    }

    static func providerIconName(for providerID: String) -> String {
        switch providerID {
        case "codex",
             "claude",
             "opencode":
            providerID
        default:
            "sparkles"
        }
    }

    static func status(for notification: DroidNotification, now: Date = Date()) -> AgentMissionControlStatus {
        let text = "\(notification.title) \(notification.body)".lowercased()
        if text.contains("fail") || text.contains("error") || text.contains("failed") {
            return .failed
        }
        if text.contains("permission") || text.contains("question") || text.contains("waiting") {
            return .needsAttention
        }
        if text.contains("complete") || text.contains("done") || text.contains("stop") || text.contains("finished") {
            return .completed
        }
        if case .aiProvider = notification.source {
            return .completed
        }
        if !notification.isRead {
            return .needsAttention
        }
        _ = now
        return .notice
    }

    private static func item(
        activity: AIActivityStore.Activity,
        projects: [Project],
        worktrees: [UUID: [Worktree]]
    ) -> AgentMissionControlItem {
        let providerName = providerName(for: activity.providerID)
        return AgentMissionControlItem(
            id: "activity:\(activity.paneID.uuidString)",
            runID: nil,
            providerID: activity.providerID,
            providerName: providerName,
            providerIconName: providerIconName(for: activity.providerID),
            sessionID: nil,
            title: "\(providerName) session",
            detail: detail(projectID: activity.projectID, worktreeID: activity.worktreeID, projects: projects, worktrees: worktrees),
            status: .running,
            timestamp: activity.startedAt,
            paneID: activity.paneID,
            notificationID: nil,
            transcriptEntries: activity.transcriptEntries,
            changedFiles: [],
            changedFilesAttribution: .none,
            verification: .notStarted
        )
    }

    private static func item(
        notification: DroidNotification,
        projects: [Project],
        worktrees: [UUID: [Worktree]],
        now: Date
    ) -> AgentMissionControlItem? {
        guard let providerID = providerID(from: notification.source) else { return nil }
        return AgentMissionControlItem(
            id: "notification:\(notification.id.uuidString)",
            runID: nil,
            providerID: providerID,
            providerName: providerName(for: providerID),
            providerIconName: providerIconName(for: providerID),
            sessionID: nil,
            title: notification.title.isEmpty ? "Agent update" : notification.title,
            detail: notification.body.isEmpty ? detail(
                projectID: notification.projectID,
                worktreeID: notification.worktreeID,
                projects: projects,
                worktrees: worktrees
            ) : notification.body,
            status: status(for: notification, now: now),
            timestamp: notification.timestamp,
            paneID: notification.paneID,
            notificationID: notification.id,
            transcriptEntries: [],
            changedFiles: [],
            changedFilesAttribution: .none,
            verification: .notStarted
        )
    }

    private static func detail(
        projectID: UUID,
        worktreeID: UUID,
        projects: [Project],
        worktrees: [UUID: [Worktree]]
    ) -> String {
        let project = projects.first { $0.id == projectID }?.name ?? "Unknown project"
        let worktree = worktrees[projectID]?.first { $0.id == worktreeID }
        let worktreeName = worktree.map(AskSessionCatalog.displayName(for:)) ?? "Unknown worktree"
        return "\(project) / \(worktreeName)"
    }

    private static func providerID(from source: DroidNotification.Source) -> String? {
        guard case let .aiProvider(id) = source else { return nil }
        return id
    }

    private static func priority(_ status: AgentMissionControlStatus) -> Int {
        switch status {
        case .needsAttention:
            0
        case .running:
            1
        case .failed:
            2
        case .completed:
            3
        case .notice:
            4
        }
    }
}
