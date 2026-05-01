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
        let startedAt: Date
        var transcriptEntries: [AgentTranscriptEntry] = []
    }

    static let shared = AIActivityStore()

    private(set) var activitiesByPaneID: [UUID: Activity] = [:]

    private init() {}

    func hasActiveAgent(projectID: UUID) -> Bool {
        activitiesByPaneID.values.contains { $0.projectID == projectID }
    }

    func start(
        providerID: String,
        paneID: UUID,
        appState: AppState,
        worktreeStore: WorktreeStore?
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
                worktreePath: context.worktreePath
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
            worktreePath: appState.activeWorktreePath[key.projectID]
        )
    }

    func start(
        providerID: String,
        paneID: UUID,
        projectID: UUID,
        worktreeID: UUID,
        worktreePath: String? = nil
    ) {
        activitiesByPaneID[paneID] = Activity(
            paneID: paneID,
            projectID: projectID,
            worktreeID: worktreeID,
            worktreePath: worktreePath,
            providerID: providerID,
            startedAt: Date()
        )
        AgentRunStore.shared.start(
            providerID: providerID,
            paneID: paneID,
            projectID: projectID,
            worktreeID: worktreeID,
            worktreePath: worktreePath
        )
    }

    @discardableResult
    func stop(paneID: UUID) -> Activity? {
        let activity = activitiesByPaneID.removeValue(forKey: paneID)
        AgentRunStore.shared.stop(paneID: paneID)
        if let activity {
            captureChangedFiles(for: activity)
        }
        return activity
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
            startedAt: run.startedAt
        ))
    }

    func pruneMissingPanes(appState: AppState) {
        let validPaneIDs = Set(
            appState.workspaces.values.flatMap { workspace in
                workspace.tabs.flatMap { workspaceTab in
                    workspaceTab.root.allAreas().flatMap { area in
                        area.tabs.compactMap { $0.content.pane?.id }
                    }
                }
            }
        )
        activitiesByPaneID = activitiesByPaneID.filter { validPaneIDs.contains($0.key) }
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

    private func hasSharedWorktreeAttribution(paneID: UUID) -> Bool {
        AgentRunStore.shared.runs.first { $0.paneID == paneID }?.changedFilesAttribution == .sharedWorktree
    }
}
