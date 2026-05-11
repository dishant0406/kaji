import Foundation

enum AgentMissionControlStatus: String, Hashable {
    case running
    case needsAttention
    case completed
    case failed
    case notice

    var title: String {
        switch self {
        case .running:
            "Running"
        case .needsAttention:
            "Needs attention"
        case .completed:
            "Completed"
        case .failed:
            "Failed"
        case .notice:
            "Notice"
        }
    }
}

struct AgentMissionControlItem: Identifiable, Hashable {
    let id: String
    let runID: UUID?
    let providerID: String
    let providerName: String
    let providerIconName: String
    let sessionID: String?
    let title: String
    let detail: String
    let status: AgentMissionControlStatus
    let timestamp: Date
    let paneID: UUID?
    let notificationID: UUID?
    let transcriptEntries: [AgentTranscriptEntry]
    let changedFiles: [AgentChangedFile]
    let changedFilesAttribution: AgentChangedFilesAttribution
    let verification: AgentVerification

    var hasChangedFileEvidence: Bool {
        changedFilesAttribution != .none || verification.status != .notStarted
    }
}

struct AgentTranscriptEntry: Identifiable, Hashable {
    let id: UUID
    let kind: String
    let text: String
    let timestamp: Date

    init(id: UUID = UUID(), kind: String, text: String, timestamp: Date = Date()) {
        self.id = id
        self.kind = kind
        self.text = text
        self.timestamp = timestamp
    }
}
