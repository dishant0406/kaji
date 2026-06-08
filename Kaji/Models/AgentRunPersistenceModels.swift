import Foundation

struct AgentRunChangedFilesManifest: Codable, Hashable {
    let totalCount: Int
    let storedCount: Int
    let chunkSize: Int
    let chunkCount: Int
}

struct AgentRunIndexRecord: Codable, Hashable {
    let run: AgentRun
    let changedFilesManifest: AgentRunChangedFilesManifest
}

struct AgentRunIndexSnapshot: Codable, Hashable {
    let version: Int
    let runs: [AgentRunIndexRecord]
}

struct AgentVerificationSummary: Codable, Hashable {
    let status: AgentVerificationStatus
    let command: String?
    let updatedAt: Date?

    init(verification: AgentVerification) {
        status = verification.status
        command = verification.command
        updatedAt = verification.updatedAt
    }

    var verification: AgentVerification {
        AgentVerification(status: status, command: command, output: nil, updatedAt: updatedAt)
    }
}

struct AgentRunIndexSummary: Codable, Hashable {
    let id: UUID
    let providerID: String
    let paneID: UUID?
    let projectID: UUID?
    let worktreeID: UUID?
    let worktreePath: String?
    let sessionID: String?
    let transcriptPath: String?
    let sessionUpdatedAt: Date?
    let title: String
    let status: AgentRunStatus
    let sourceConfidence: AgentSourceConfidence
    let changedFilesAttribution: AgentChangedFilesAttribution
    let changedFilesManifest: AgentRunChangedFilesManifest
    let verification: AgentVerificationSummary
    let startedAt: Date
    let lastEventAt: Date
    let eventCount: Int
    let actionCount: Int

    init(run: AgentRun, changedFilesManifest: AgentRunChangedFilesManifest, detail: AgentRunDetailSnapshot) {
        id = run.id
        providerID = run.providerID
        paneID = run.paneID
        projectID = run.projectID
        worktreeID = run.worktreeID
        worktreePath = run.worktreePath
        sessionID = run.sessionID
        transcriptPath = run.transcriptPath
        sessionUpdatedAt = run.sessionUpdatedAt
        title = run.title
        status = run.status
        sourceConfidence = run.sourceConfidence
        changedFilesAttribution = run.changedFilesAttribution
        self.changedFilesManifest = changedFilesManifest
        verification = AgentVerificationSummary(verification: detail.verification)
        startedAt = run.startedAt
        lastEventAt = run.lastEventAt
        eventCount = detail.events.count
        actionCount = detail.actions.count
    }
}

struct AgentRunDetailSnapshot: Codable, Hashable {
    let events: [AgentRunEvent]
    let actions: [AgentRunActionRecord]
    let verification: AgentVerification
    let changedFilesPreview: [AgentChangedFile]
}

struct AgentRunIndexSnapshotV2: Codable, Hashable {
    let version: Int
    let runs: [AgentRunIndexSummary]
}
