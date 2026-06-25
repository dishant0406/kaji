import Foundation

@MainActor
@Observable
final class AIActivityStore {
    struct Activity: Equatable {
        let paneID: UUID
        let projectID: UUID
        let worktreeID: UUID
        let worktreePath: String?
        let providerID: String
        let sessionID: String?
        let turnID: String?
        let startedAt: Date
        var lastEventAt: Date
        var transcriptEntries: [AgentTranscriptEntry] = []

        init(
            paneID: UUID,
            projectID: UUID,
            worktreeID: UUID,
            worktreePath: String?,
            providerID: String,
            sessionID: String? = nil,
            turnID: String? = nil,
            startedAt: Date,
            lastEventAt: Date = Date(),
            transcriptEntries: [AgentTranscriptEntry] = []
        ) {
            self.paneID = paneID
            self.projectID = projectID
            self.worktreeID = worktreeID
            self.worktreePath = worktreePath
            self.providerID = providerID
            self.sessionID = sessionID
            self.turnID = turnID
            self.startedAt = startedAt
            self.lastEventAt = lastEventAt
            self.transcriptEntries = transcriptEntries
        }
    }

    static let shared = AIActivityStore()

    private(set) var activitiesByPaneID: [UUID: Activity] = [:]

    private init() {}

    func hasActiveAgent(projectID: UUID) -> Bool {
        activitiesByPaneID.values.contains { $0.projectID == projectID }
    }

    func hasActiveAgent(projectID: UUID, worktreeID: UUID) -> Bool {
        activitiesByPaneID.values.contains { activity in
            activity.projectID == projectID && activity.worktreeID == worktreeID
        }
    }

    func start(
        providerID: String,
        paneID: UUID,
        appState: AppState,
        worktreeStore: WorktreeStore?,
        sessionID: String? = nil,
        turnID: String? = nil
    ) {
        if let worktreeStore,
           let context = NotificationNavigator.resolveContext(
               for: paneID,
               appState: appState,
               worktreeStore: worktreeStore
           )
        {
            start(
                providerID: providerID,
                paneID: paneID,
                projectID: context.projectID,
                worktreeID: context.worktreeID,
                worktreePath: context.worktreePath,
                sessionID: sessionID,
                turnID: turnID
            )
            return
        }

        guard let projectID = appState.activeProjectID,
              let key = appState.activeWorktreeKey(for: projectID)
        else {
            return
        }

        start(
            providerID: providerID,
            paneID: paneID,
            projectID: key.projectID,
            worktreeID: key.worktreeID,
            worktreePath: appState.activeWorktreePath[key.projectID],
            sessionID: sessionID,
            turnID: turnID
        )
    }

    func start(
        providerID: String,
        paneID: UUID,
        projectID: UUID,
        worktreeID: UUID,
        worktreePath: String? = nil,
        sessionID: String? = nil,
        turnID: String? = nil
    ) {
        let now = Date()
        activitiesByPaneID[paneID] = Activity(
            paneID: paneID,
            projectID: projectID,
            worktreeID: worktreeID,
            worktreePath: worktreePath,
            providerID: providerID,
            sessionID: sessionID,
            turnID: turnID,
            startedAt: now,
            lastEventAt: now
        )
        AgentRunStore.shared.start(
            providerID: providerID,
            paneID: paneID,
            projectID: projectID,
            worktreeID: worktreeID,
            worktreePath: worktreePath
        )
    }

    func observe(providerID: String, paneID: UUID, sessionID: String? = nil, turnID: String? = nil) {
        guard var activity = activitiesByPaneID[paneID], activity.providerID == providerID else { return }
        guard matches(activity: activity, sessionID: sessionID, turnID: turnID) else { return }
        activity.lastEventAt = Date()
        activitiesByPaneID[paneID] = activity
    }

    @discardableResult
    func stop(paneID: UUID, sessionID: String? = nil, turnID: String? = nil) -> Activity? {
        guard let existing = activitiesByPaneID[paneID], matches(activity: existing, sessionID: sessionID, turnID: turnID) else {
            return nil
        }
        let activity = activitiesByPaneID.removeValue(forKey: paneID)
        AgentRunStore.shared.stop(paneID: paneID)
        if let activity {
            captureChangedFiles(for: activity)
        }
        return activity
    }

    func markStale(paneID: UUID, message: String) {
        guard let activity = activitiesByPaneID.removeValue(forKey: paneID) else { return }
        AgentRunStore.shared.markStale(providerID: activity.providerID, paneID: paneID, message: message)
        captureChangedFiles(for: activity)
    }

    func clearLiveActivities(markRunsStale: Bool, message: String) {
        let activities = Array(activitiesByPaneID.values)
        activitiesByPaneID.removeAll()
        guard markRunsStale else { return }
        for activity in activities {
            AgentRunStore.shared.markStale(providerID: activity.providerID, paneID: activity.paneID, message: message)
            captureChangedFiles(for: activity)
        }
    }

    func markActivitiesStale(where shouldMark: (Activity) -> Bool, message: String) {
        let activities = activitiesByPaneID.values.filter(shouldMark)
        for activity in activities {
            markStale(paneID: activity.paneID, message: message)
        }
    }

    func appendTranscript(providerID: String, paneID: UUID, kind: String, text: String) {
        guard var activity = activitiesByPaneID[paneID], activity.providerID == providerID else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let entry = AgentTranscriptEntry(kind: kind.isEmpty ? "update" : kind, text: trimmed)
        activity.transcriptEntries = Array((activity.transcriptEntries + [entry]).suffix(8))
        activitiesByPaneID[paneID] = activity
        AgentRunStore.shared.appendTranscript(providerID: providerID, paneID: paneID, kind: kind, text: trimmed)
    }

    func recordAttention(providerID: String, paneID: UUID, kind: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = trimmed.isEmpty ? "Needs attention" : trimmed
        if var activity = activitiesByPaneID[paneID], activity.providerID == providerID {
            let entry = AgentTranscriptEntry(kind: kind.isEmpty ? "attention" : kind, text: detail)
            activity.transcriptEntries = Array((activity.transcriptEntries + [entry]).suffix(8))
            activitiesByPaneID[paneID] = activity
        }
        AgentRunStore.shared.recordAttention(providerID: providerID, paneID: paneID, kind: kind, text: detail)
    }

    func stop(
        providerID: String,
        projectID: UUID,
        worktreeID: UUID
    ) {
        let matchingActivities = activitiesByPaneID.values.filter { activity in
            activity.providerID == providerID &&
                activity.projectID == projectID &&
                activity.worktreeID == worktreeID
        }
        activitiesByPaneID = activitiesByPaneID.filter { _, activity in
            !(activity.providerID == providerID &&
                activity.projectID == projectID &&
                activity.worktreeID == worktreeID)
        }
        AgentRunStore.shared.stop(providerID: providerID, projectID: projectID, worktreeID: worktreeID)
        for activity in matchingActivities {
            captureChangedFiles(for: activity)
        }
    }

    func stop(
        providerID: String,
        projectID: UUID
    ) {
        let matchingActivities = activitiesByPaneID.values.filter { activity in
            activity.providerID == providerID && activity.projectID == projectID
        }
        activitiesByPaneID = activitiesByPaneID.filter { _, activity in
            !(activity.providerID == providerID &&
                activity.projectID == projectID)
        }
        AgentRunStore.shared.stop(providerID: providerID, projectID: projectID)
        for activity in matchingActivities {
            captureChangedFiles(for: activity)
        }
    }

    func reset() {
        activitiesByPaneID.removeAll()
        AgentRunStore.shared.reset()
    }

    func captureChangedFiles(providerID: String, paneID: UUID) {
        guard let run = AgentRunStore.shared.run(providerID: providerID, paneID: paneID),
              let projectID = run.projectID,
              let worktreeID = run.worktreeID
        else { return }
        captureChangedFiles(for: Activity(
            paneID: paneID,
            projectID: projectID,
            worktreeID: worktreeID,
            worktreePath: run.worktreePath,
            providerID: providerID,
            sessionID: nil,
            turnID: nil,
            startedAt: run.startedAt,
            lastEventAt: Date()
        ))
    }

    func pruneMissingPanes(appState: AppState) {
        let validPaneIDs = Set(
            appState.workspaces.values.flatMap { workspace in
                workspace.tabs.flatMap { workspaceTab in
                    workspaceTab.root.allAreas().flatMap { area in
                        area.tabs.compactMap { tab in
                            tab.content.pane?.id ?? tab.content.parentAgentState?.id
                        }
                    }
                }
            }
        )
        markActivitiesStale(where: { !validPaneIDs.contains($0.paneID) }, message: "Agent terminal pane disappeared.")
    }

    private func captureChangedFiles(for activity: Activity) {
        guard let worktreePath = activity.worktreePath else {
            AgentRunStore.shared.setChangedFiles(
                providerID: activity.providerID,
                paneID: activity.paneID,
                files: [],
                attribution: .unavailable
            )
            return
        }

        if AgentRunStore.shared.hasConcurrentOpenRun(
            paneID: activity.paneID,
            projectID: activity.projectID,
            worktreeID: activity.worktreeID
        ) || hasSharedWorktreeAttribution(paneID: activity.paneID) {
            AgentRunStore.shared.setChangedFiles(
                providerID: activity.providerID,
                paneID: activity.paneID,
                files: [],
                attribution: .sharedWorktree
            )
            return
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: worktreePath, isDirectory: &isDirectory), isDirectory.boolValue else {
            AgentRunStore.shared.setChangedFiles(
                providerID: activity.providerID,
                paneID: activity.paneID,
                files: [],
                attribution: .unavailable
            )
            return
        }

        Task {
            let files = await AgentChangedFilesSnapshotter.snapshot(repoPath: worktreePath)
            await MainActor.run {
                AgentRunStore.shared.setChangedFiles(
                    providerID: activity.providerID,
                    paneID: activity.paneID,
                    files: files ?? [],
                    attribution: files == nil ? .unavailable : .worktreeSnapshot
                )
            }
        }
    }

    private func matches(activity: Activity, sessionID: String?, turnID: String?) -> Bool {
        if let sessionID, let activeSessionID = activity.sessionID, sessionID != activeSessionID { return false }
        if let turnID, let activeTurnID = activity.turnID, turnID != activeTurnID { return false }
        return true
    }

    private func hasSharedWorktreeAttribution(paneID: UUID) -> Bool {
        AgentRunStore.shared.runs.first { $0.paneID == paneID }?.changedFilesAttribution == .sharedWorktree
    }
}
