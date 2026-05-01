import Foundation

@MainActor
@Observable
final class AgentRunStore {
    static let shared = AgentRunStore()

    private(set) var runs: [AgentRun] = []

    private let maxRuns = 80
    private let maxEventsPerRun = 40

    private init() {}

    func start(
        providerID: String,
        paneID: UUID,
        projectID: UUID,
        worktreeID: UUID,
        worktreePath: String? = nil,
        title: String? = nil,
        confidence: AgentSourceConfidence = .exactPane
    ) {
        removeActiveRun(providerID: providerID, paneID: paneID)
        let sharedWorktree = hasConcurrentOpenRun(paneID: paneID, projectID: projectID, worktreeID: worktreeID)
        if sharedWorktree {
            markSharedWorktree(projectID: projectID, worktreeID: worktreeID)
        }
        let now = Date()
        let run = AgentRun(
            id: UUID(),
            providerID: providerID,
            paneID: paneID,
            projectID: projectID,
            worktreeID: worktreeID,
            worktreePath: worktreePath,
            title: title ?? AgentMissionControlSnapshotBuilder.providerName(for: providerID),
            status: .running,
            sourceConfidence: confidence,
            changedFiles: [],
            changedFilesAttribution: sharedWorktree ? .sharedWorktree : .none,
            verification: .notStarted,
            startedAt: now,
            lastEventAt: now,
            events: [AgentRunEvent(kind: .started, label: "start", text: "Started")]
        )
        runs.insert(run, at: 0)
        trimRuns()
    }

    func stop(paneID: UUID) {
        updateRun(paneID: paneID) { run in
            guard isOpen(run.status) else { return }
            appendEvent(.init(kind: .stopped, label: "stop", text: "Stopped"), to: &run)
            run.status = .completed
        }
    }

    func stop(providerID: String, projectID: UUID, worktreeID: UUID) {
        updateRun(providerID: providerID, projectID: projectID, worktreeID: worktreeID) { run in
            guard isOpen(run.status) else { return }
            appendEvent(.init(kind: .stopped, label: "stop", text: "Stopped"), to: &run)
            run.status = .completed
        }
    }

    func stop(providerID: String, projectID: UUID) {
        let matchingIndexes = runs.indices.filter { index in
            runs[index].providerID == providerID &&
                runs[index].projectID == projectID &&
                isOpen(runs[index].status)
        }
        for index in matchingIndexes {
            appendEvent(.init(kind: .stopped, label: "stop", text: "Stopped"), to: &runs[index])
            runs[index].status = .completed
        }
    }

    func complete(providerID: String, paneID: UUID, message: String) {
        updateRun(providerID: providerID, paneID: paneID) { run in
            appendEvent(.init(kind: .completed, label: "done", text: message), to: &run)
            run.status = .completed
        }
    }

    func fail(providerID: String, paneID: UUID, message: String) {
        updateRun(providerID: providerID, paneID: paneID) { run in
            appendEvent(.init(kind: .failed, label: "failed", text: message), to: &run)
            run.status = .failed
        }
    }

    func appendTranscript(providerID: String, paneID: UUID, kind: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateRun(providerID: providerID, paneID: paneID) { run in
            let label = kind.isEmpty ? "update" : kind
            let eventKind: AgentRunEventKind = label == "attention" ? .attention : .transcript
            appendEvent(.init(kind: eventKind, label: label, text: trimmed), to: &run)
            if eventKind == .attention {
                run.status = .needsAttention
            }
        }
    }

    func setChangedFiles(
        providerID: String,
        paneID: UUID,
        files: [AgentChangedFile],
        attribution: AgentChangedFilesAttribution
    ) {
        updateRun(providerID: providerID, paneID: paneID) { run in
            run.changedFiles = files
            run.changedFilesAttribution = attribution
            let message = changedFilesMessage(count: files.count, attribution: attribution)
            appendEvent(.init(kind: .fileChange, label: "files", text: message), to: &run)
        }
    }

    func hasConcurrentOpenRun(paneID: UUID, projectID: UUID, worktreeID: UUID) -> Bool {
        runs.contains { run in
            run.paneID != paneID &&
                run.projectID == projectID &&
                run.worktreeID == worktreeID &&
                isOpen(run.status)
        }
    }

    func reset() {
        runs.removeAll()
    }

    func run(id: UUID) -> AgentRun? {
        runs.first { $0.id == id }
    }

    func startVerification(runID: UUID, command: String) {
        updateRun(id: runID) { run in
            run.verification = AgentVerification(status: .running, command: command, output: nil, updatedAt: Date())
        }
    }

    func finishVerification(runID: UUID, status: AgentVerificationStatus, output: String) {
        updateRun(id: runID) { run in
            let command = run.verification.command
            run.verification = AgentVerification(status: status, command: command, output: output, updatedAt: Date())
        }
    }

    private func removeActiveRun(providerID: String, paneID: UUID) {
        runs.removeAll { run in
            run.providerID == providerID &&
                run.paneID == paneID &&
                isOpen(run.status)
        }
    }

    private func markSharedWorktree(projectID: UUID, worktreeID: UUID) {
        let matchingIndexes = runs.indices.filter { index in
            runs[index].projectID == projectID &&
                runs[index].worktreeID == worktreeID &&
                isOpen(runs[index].status)
        }
        for index in matchingIndexes {
            runs[index].changedFilesAttribution = .sharedWorktree
        }
    }

    private func updateRun(paneID: UUID, update: (inout AgentRun) -> Void) {
        guard let index = runs.firstIndex(where: { $0.paneID == paneID }) else { return }
        update(&runs[index])
    }

    private func updateRun(providerID: String, paneID: UUID, update: (inout AgentRun) -> Void) {
        guard let index = runs.firstIndex(where: { $0.providerID == providerID && $0.paneID == paneID }) else { return }
        update(&runs[index])
    }

    private func updateRun(id: UUID, update: (inout AgentRun) -> Void) {
        guard let index = runs.firstIndex(where: { $0.id == id }) else { return }
        update(&runs[index])
    }

    private func updateRun(
        providerID: String,
        projectID: UUID,
        worktreeID: UUID,
        update: (inout AgentRun) -> Void
    ) {
        guard let index = runs.firstIndex(where: {
            $0.providerID == providerID && $0.projectID == projectID && $0.worktreeID == worktreeID
        })
        else { return }
        update(&runs[index])
    }

    private func appendEvent(_ event: AgentRunEvent, to run: inout AgentRun) {
        run.events = Array((run.events + [event]).suffix(maxEventsPerRun))
        run.lastEventAt = event.timestamp
    }

    private func trimRuns() {
        guard runs.count > maxRuns else { return }
        runs = Array(runs.prefix(maxRuns))
    }

    private func isOpen(_ status: AgentRunStatus) -> Bool {
        status == .running || status == .waiting || status == .needsAttention
    }

    private func changedFilesMessage(count: Int, attribution: AgentChangedFilesAttribution) -> String {
        switch attribution {
        case .none:
            "No changed files"
        case .providerReported:
            "\(count) provider-reported changed \(count == 1 ? "file" : "files")"
        case .worktreeSnapshot:
            "\(count) worktree changed \(count == 1 ? "file" : "files")"
        case .sharedWorktree:
            "Shared worktree; exact files unavailable"
        case .unavailable:
            "Changed files unavailable"
        }
    }
}
