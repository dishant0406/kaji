import Foundation

@MainActor
enum AgentRunMissionControlSnapshotBuilder {
    static func items(
        runs: [AgentRun],
        notifications: [DroidNotification],
        projects: [Project],
        worktrees: [UUID: [Worktree]],
        now: Date = Date(),
        limit: Int = 30
    ) -> [AgentMissionControlItem] {
        let completedNotifications = notifications.filter(isCompletedProviderNotification)
        let runItems = runs.map { run in
            let completion = latestCompletion(for: run, notifications: completedNotifications)
            return item(run: run, completion: completion, projects: projects, worktrees: worktrees, now: now)
        }
        let runPaneIDs = Set(runItems.compactMap(\.paneID))
        let runContexts = Set(runs.compactMap(runContextKey))
        let fallbackItems: [AgentMissionControlItem] = notifications.prefix(limit).compactMap { notification in
            guard !runPaneIDs.contains(notification.paneID) else { return nil }
            guard !runContexts.contains(notificationContextKey(notification)) else { return nil }
            return item(notification: notification, projects: projects, worktrees: worktrees, now: now)
        }
        return (runItems + fallbackItems)
            .sorted { lhs, rhs in
                if lhs.status != rhs.status {
                    return priority(lhs.status) < priority(rhs.status)
                }
                return lhs.timestamp > rhs.timestamp
            }
            .prefix(limit)
            .map(\.self)
    }

    static func item(
        run: AgentRun,
        completion: DroidNotification? = nil,
        projects: [Project],
        worktrees: [UUID: [Worktree]],
        now: Date = Date()
    ) -> AgentMissionControlItem {
        let providerName = AgentMissionControlSnapshotBuilder.providerName(for: run.providerID)
        let resolvedStatus = completion == nil ? status(for: run.status) : .completed
        let resolvedTimestamp = completion?.timestamp ?? run.lastEventAt
        return AgentMissionControlItem(
            id: "run:\(run.id.uuidString)",
            runID: run.id,
            providerID: run.providerID,
            providerName: providerName,
            providerIconName: AgentMissionControlSnapshotBuilder.providerIconName(for: run.providerID),
            sessionID: run.sessionID,
            title: run.title.isEmpty ? "\(providerName) session" : run.title,
            detail: detail(run: run, completion: completion, projects: projects, worktrees: worktrees, now: now),
            status: resolvedStatus,
            timestamp: resolvedTimestamp,
            paneID: run.paneID,
            notificationID: nil,
            transcriptEntries: transcriptEntries(from: run),
            changedFiles: run.changedFiles,
            changedFilesAttribution: run.changedFilesAttribution,
            verification: run.verification
        )
    }

    private static func item(
        notification: DroidNotification,
        projects: [Project],
        worktrees: [UUID: [Worktree]],
        now: Date
    ) -> AgentMissionControlItem? {
        guard case let .aiProvider(providerID) = notification.source else { return nil }
        let fallbackDetail = locationDetail(
            projectID: notification.projectID,
            worktreeID: notification.worktreeID,
            projects: projects,
            worktrees: worktrees
        )
        return AgentMissionControlItem(
            id: "notification:\(notification.id.uuidString)",
            runID: nil,
            providerID: providerID,
            providerName: AgentMissionControlSnapshotBuilder.providerName(for: providerID),
            providerIconName: AgentMissionControlSnapshotBuilder.providerIconName(for: providerID),
            sessionID: nil,
            title: notification.title.isEmpty ? "Agent update" : notification.title,
            detail: notification.body.isEmpty ? fallbackDetail : notification.body,
            status: AgentMissionControlSnapshotBuilder.status(for: notification, now: now),
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
        run: AgentRun,
        completion: DroidNotification? = nil,
        projects: [Project],
        worktrees: [UUID: [Worktree]],
        now: Date
    ) -> String {
        let location = if let projectID = run.projectID, let worktreeID = run.worktreeID {
            locationDetail(projectID: projectID, worktreeID: worktreeID, projects: projects, worktrees: worktrees)
        } else {
            "Detached session"
        }
        let base = "\(location) · \(elapsedTime(from: run.startedAt, to: now))"
        let completionSummary = completion.flatMap { notification in
            notification.body.isEmpty ? "completed" : notification.body
        }
        let evidence = [completionSummary, changedFilesSummary(for: run), verificationSummary(for: run)].compactMap(\.self)
        guard !evidence.isEmpty else { return base }
        return "\(base) · \(evidence.joined(separator: " · "))"
    }

    private static func locationDetail(
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

    private static func status(for status: AgentRunStatus) -> AgentMissionControlStatus {
        switch status {
        case .running,
             .waiting:
            .running
        case .needsAttention:
            .needsAttention
        case .completed,
             .stale:
            .completed
        case .failed:
            .failed
        }
    }

    private static func transcriptEntries(from run: AgentRun) -> [AgentTranscriptEntry] {
        run.events.filter { $0.kind == .transcript || $0.kind == .attention }.suffix(8).map { event in
            AgentTranscriptEntry(id: event.id, kind: event.label, text: event.text, timestamp: event.timestamp)
        }
    }

    private static func elapsedTime(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h"
    }

    private static func changedFilesSummary(for run: AgentRun) -> String? {
        switch run.changedFilesAttribution {
        case .none:
            nil
        case .providerReported:
            fileCountSummary(run.changedFiles.count)
        case .worktreeSnapshot:
            "\(fileCountSummary(run.changedFiles.count)) snapshot"
        case .sharedWorktree:
            "shared worktree"
        case .unavailable:
            "files unavailable"
        }
    }

    private static func fileCountSummary(_ count: Int) -> String {
        "\(count) \(count == 1 ? "file" : "files") changed"
    }

    private static func verificationSummary(for run: AgentRun) -> String? {
        switch run.verification.status {
        case .notStarted:
            nil
        case .running:
            "verifying"
        case .passed:
            "verified"
        case .failed:
            "verification failed"
        case .unavailable:
            "verification unavailable"
        }
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

    private static func runContextKey(_ run: AgentRun) -> String? {
        guard let projectID = run.projectID, let worktreeID = run.worktreeID else { return nil }
        return "\(run.providerID)|\(projectID.uuidString)|\(worktreeID.uuidString)"
    }

    private static func notificationContextKey(_ notification: DroidNotification) -> String {
        let providerID = if case let .aiProvider(id) = notification.source { id } else { "" }
        return "\(providerID)|\(notification.projectID.uuidString)|\(notification.worktreeID.uuidString)"
    }

    private static func latestCompletion(for run: AgentRun, notifications: [DroidNotification]) -> DroidNotification? {
        notifications
            .filter { notification in
                notification.timestamp >= run.startedAt && matches(run: run, notification: notification)
            }
            .max { lhs, rhs in lhs.timestamp < rhs.timestamp }
    }

    private static func matches(run: AgentRun, notification: DroidNotification) -> Bool {
        guard case let .aiProvider(providerID) = notification.source, providerID == run.providerID else { return false }
        if let paneID = run.paneID, paneID == notification.paneID { return true }
        guard let projectID = run.projectID, let worktreeID = run.worktreeID else { return false }
        return notification.projectID == projectID && notification.worktreeID == worktreeID
    }

    private static func isCompletedProviderNotification(_ notification: DroidNotification) -> Bool {
        guard case .aiProvider = notification.source else { return false }
        return AgentMissionControlSnapshotBuilder.status(for: notification) == .completed
    }
}
