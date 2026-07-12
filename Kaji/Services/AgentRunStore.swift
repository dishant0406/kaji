import Foundation

@MainActor
@Observable
final class AgentRunStore {
    static let shared = AgentRunStore(persistence: defaultPersistence())

    private(set) var runs: [AgentRun] = []

    @ObservationIgnored private let fileStore: CodableFileStore<[AgentRun]>?
    @ObservationIgnored private let persistence: AgentRunPersistence?
    private let maxRuns = 80
    private let maxEventsPerRun = 40
    private let maxActionsPerRun = 40
    private let restartGraceInterval: TimeInterval = 2

    init(
        fileStore: CodableFileStore<[AgentRun]>? = nil,
        persistence: AgentRunPersistence? = nil
    ) {
        self.fileStore = fileStore
        self.persistence = persistence
        runs = Self.loadRuns(from: fileStore, persistence: persistence)
        trimRuns()
    }

    func start(
        providerID: String,
        paneID: UUID,
        projectID: UUID,
        worktreeID: UUID,
        worktreePath: String? = nil,
        title: String? = nil,
        confidence: AgentSourceConfidence = .exactPane
    ) {
        if ignoresLateRestart(providerID: providerID, paneID: paneID) {
            return
        }
        if updateExistingOpenRun(.init(
            providerID: providerID,
            paneID: paneID,
            projectID: projectID,
            worktreeID: worktreeID,
            worktreePath: worktreePath,
            title: title,
            confidence: confidence
        )) {
            persist()
            return
        }
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
            events: [AgentRunEvent(kind: .started, label: "start", text: "Started")],
            actions: []
        )
        runs.insert(run, at: 0)
        trimRuns()
        persist()
    }

    func stop(paneID: UUID) {
        updateRuns(paneID: paneID, openOnly: true) { run in
            appendEvent(.init(kind: .stopped, label: "stop", text: "Stopped"), to: &run)
            run.status = .completed
        }
        persist()
    }

    func markStale(providerID: String, paneID: UUID, message: String) {
        updateRuns(providerID: providerID, paneID: paneID, openOnly: true) { run in
            appendEvent(.init(kind: .stopped, label: "stale", text: message), to: &run)
            run.status = .stale
        }
        persist()
    }

    func stop(providerID: String, projectID: UUID, worktreeID: UUID) {
        updateRuns(providerID: providerID, projectID: projectID, worktreeID: worktreeID, openOnly: true) { run in
            appendEvent(.init(kind: .stopped, label: "stop", text: "Stopped"), to: &run)
            run.status = .completed
        }
        persist()
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
        persist()
    }

    func markProjectStale(projectID: UUID, message: String) {
        let matchingIndexes = runs.indices.filter { index in
            runs[index].projectID == projectID && isOpen(runs[index].status)
        }
        for index in matchingIndexes {
            appendEvent(.init(kind: .stopped, label: "stale", text: message), to: &runs[index])
            runs[index].status = .stale
        }
        persist()
    }

    func complete(providerID: String, paneID: UUID, message: String) {
        if updateRuns(providerID: providerID, paneID: paneID, openOnly: true, update: { run in
            appendEvent(.init(kind: .completed, label: "done", text: message), to: &run)
            run.status = .completed
        }) {
            persist()
            return
        }

        updateRun(providerID: providerID, paneID: paneID) { run in
            appendEvent(.init(kind: .completed, label: "done", text: message), to: &run)
            run.status = .completed
        }
        persist()
    }

    func complete(providerID: String, projectID: UUID, worktreeID: UUID, message: String) {
        if updateRuns(providerID: providerID, projectID: projectID, worktreeID: worktreeID, openOnly: true, update: { run in
            appendEvent(.init(kind: .completed, label: "done", text: message), to: &run)
            run.status = .completed
        }) {
            persist()
            return
        }

        updateRun(providerID: providerID, projectID: projectID, worktreeID: worktreeID) { run in
            appendEvent(.init(kind: .completed, label: "done", text: message), to: &run)
            run.status = .completed
        }
        persist()
    }

    func fail(providerID: String, paneID: UUID, message: String) {
        updateRun(providerID: providerID, paneID: paneID) { run in
            appendEvent(.init(kind: .failed, label: "failed", text: message), to: &run)
            run.status = .failed
        }
        persist()
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
            } else if run.status == .needsAttention {
                run.status = .running
            }
        }
        persist()
    }

    func recordAttention(providerID: String, paneID: UUID, kind: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateRun(providerID: providerID, paneID: paneID) { run in
            let label = kind.isEmpty ? "attention" : kind
            appendEvent(.init(kind: .attention, label: label, text: trimmed), to: &run)
            run.status = .needsAttention
        }
        persist()
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
        persist()
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
        persist()
    }

    func run(id: UUID) -> AgentRun? {
        runs.first { $0.id == id }
    }

    func run(providerID: String, paneID: UUID) -> AgentRun? {
        runs.first { $0.providerID == providerID && $0.paneID == paneID && isOpen($0.status) }
            ?? runs.first { $0.providerID == providerID && $0.paneID == paneID }
    }

    func setSessionMetadata(_ metadata: CodingAgentSessionMetadata) {
        guard let index = runs.firstIndex(where: { run in
            run.providerID == metadata.providerID && run.paneID == metadata.paneID && isOpen(run.status)
        }) ?? runs.firstIndex(where: { run in
            run.providerID == metadata.providerID && run.paneID == metadata.paneID
        })
        else { return }
        runs[index].sessionID = metadata.sessionID
        runs[index].transcriptPath = metadata.transcriptPath
        runs[index].sessionUpdatedAt = metadata.updatedAt
        if let title = metadata.title, !title.isEmpty {
            runs[index].title = title
        }
        runs[index].lastEventAt = metadata.updatedAt
        persist()
    }

    func startVerification(runID: UUID, command: String) {
        updateRun(id: runID) { run in
            run.verification = AgentVerification(status: .running, command: command, output: nil, updatedAt: Date())
        }
        persist()
    }

    func finishVerification(runID: UUID, status: AgentVerificationStatus, output: String) {
        updateRun(id: runID) { run in
            let command = run.verification.command
            run.verification = AgentVerification(status: status, command: command, output: output, updatedAt: Date())
        }
        persist()
    }

    func recordAction(runID: UUID, kind: AgentRunActionKind, status: AgentRunActionStatus, message: String) {
        updateRun(id: runID) { run in
            let action = AgentRunActionRecord(kind: kind, status: status, message: message)
            run.actions = Array((run.actions + [action]).suffix(maxActionsPerRun))
        }
        persist()
    }

    func flushPersistence() {
        if let persistence {
            persistence.saveSynchronously(runs)
            return
        }
        try? fileStore?.save(runs)
    }

    private static func defaultPersistence() -> AgentRunPersistence? {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
            ProcessInfo.processInfo.processName.hasSuffix("PackageTests")
        {
            return nil
        }
        return AgentRunPersistence()
    }

    private static func loadRuns(
        from fileStore: CodableFileStore<[AgentRun]>?,
        persistence: AgentRunPersistence?
    ) -> [AgentRun] {
        if let persistence {
            return persistence.loadRuns().map(normalizedPersistedRun)
        }
        guard let fileStore, let loaded = try? fileStore.load() else { return [] }
        return loaded.map(normalizedPersistedRun)
    }

    private static func normalizedPersistedRun(_ run: AgentRun) -> AgentRun {
        var run = run
        if run.status == .running || run.status == .waiting || run.status == .needsAttention {
            run.status = .stale
        }
        if run.verification.status == .running {
            run.verification = AgentVerification(
                status: .unavailable,
                command: run.verification.command,
                output: "Verification was interrupted.",
                updatedAt: Date()
            )
        }
        return run
    }

    private func persist() {
        if let persistence {
            persistence.scheduleSave(runs)
            return
        }
        try? fileStore?.save(runs)
    }

    private func removeActiveRun(providerID: String, paneID: UUID) {
        runs.removeAll { run in
            run.providerID == providerID &&
                run.paneID == paneID &&
                isOpen(run.status)
        }
    }

    private struct OpenRunUpdate {
        let providerID: String
        let paneID: UUID
        let projectID: UUID
        let worktreeID: UUID
        let worktreePath: String?
        let title: String?
        let confidence: AgentSourceConfidence
    }

    private func updateExistingOpenRun(_ update: OpenRunUpdate) -> Bool {
        guard let index = runs.firstIndex(where: { run in
            run.providerID == update.providerID && run.paneID == update.paneID && isOpen(run.status)
        })
        else { return false }
        runs[index].projectID = update.projectID
        runs[index].worktreeID = update.worktreeID
        runs[index].worktreePath = update.worktreePath
        if let title = update.title, !title.isEmpty {
            runs[index].title = title
        }
        runs[index].sourceConfidence = update.confidence
        runs[index].lastEventAt = Date()
        return true
    }

    private func ignoresLateRestart(providerID: String, paneID: UUID) -> Bool {
        guard let run = runs.first(where: { $0.providerID == providerID && $0.paneID == paneID }) else { return false }
        guard !isOpen(run.status) else { return false }
        guard run.events.last?.kind == .completed else { return false }
        return Date().timeIntervalSince(run.lastEventAt) < restartGraceInterval
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
        let openIndex = runs.firstIndex { $0.paneID == paneID && isOpen($0.status) }
        let fallbackIndex = runs.firstIndex { $0.paneID == paneID }
        guard let index = openIndex ?? fallbackIndex else { return }
        update(&runs[index])
    }

    @discardableResult
    private func updateRuns(paneID: UUID, openOnly: Bool, update: (inout AgentRun) -> Void) -> Bool {
        let indexes = runs.indices.filter { index in
            runs[index].paneID == paneID && (!openOnly || isOpen(runs[index].status))
        }
        guard !indexes.isEmpty else { return false }
        for index in indexes {
            update(&runs[index])
        }
        return true
    }

    private func updateRun(providerID: String, paneID: UUID, update: (inout AgentRun) -> Void) {
        let openIndex = runs.firstIndex { $0.providerID == providerID && $0.paneID == paneID && isOpen($0.status) }
        let fallbackIndex = runs.firstIndex { $0.providerID == providerID && $0.paneID == paneID }
        guard let index = openIndex ?? fallbackIndex else { return }
        update(&runs[index])
    }

    @discardableResult
    private func updateRuns(providerID: String, paneID: UUID, openOnly: Bool, update: (inout AgentRun) -> Void) -> Bool {
        let indexes = runs.indices.filter { index in
            runs[index].providerID == providerID &&
                runs[index].paneID == paneID &&
                (!openOnly || isOpen(runs[index].status))
        }
        guard !indexes.isEmpty else { return false }
        for index in indexes {
            update(&runs[index])
        }
        return true
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
        let openIndex = runs.firstIndex {
            $0.providerID == providerID && $0.projectID == projectID && $0.worktreeID == worktreeID && isOpen($0.status)
        }
        let fallbackIndex = runs.firstIndex {
            $0.providerID == providerID && $0.projectID == projectID && $0.worktreeID == worktreeID
        }
        guard let index = openIndex ?? fallbackIndex else { return }
        update(&runs[index])
    }

    @discardableResult
    private func updateRuns(
        providerID: String,
        projectID: UUID,
        worktreeID: UUID,
        openOnly: Bool,
        update: (inout AgentRun) -> Void
    ) -> Bool {
        let indexes = runs.indices.filter { index in
            runs[index].providerID == providerID &&
                runs[index].projectID == projectID &&
                runs[index].worktreeID == worktreeID &&
                (!openOnly || isOpen(runs[index].status))
        }
        guard !indexes.isEmpty else { return false }
        for index in indexes {
            update(&runs[index])
        }
        return true
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
