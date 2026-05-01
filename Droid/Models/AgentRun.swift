import Foundation

enum AgentRunStatus: String, Codable, Hashable {
    case running
    case waiting
    case needsAttention
    case completed
    case failed
    case stale
}

enum AgentSourceConfidence: String, Codable, Hashable {
    case exactPane
    case exactSession
    case worktreeMatch
    case fallback
    case unknown
}

enum AgentRunEventKind: String, Codable, Hashable {
    case started
    case transcript
    case attention
    case fileChange
    case completed
    case failed
    case stopped
}

enum AgentChangedFileStatus: String, Codable, Hashable {
    case added
    case modified
    case deleted
    case renamed
    case copied
    case untracked
    case conflicted
    case unknown
}

enum AgentChangedFilesAttribution: String, Codable, Hashable {
    case none
    case providerReported
    case worktreeSnapshot
    case sharedWorktree
    case unavailable

    var isExact: Bool {
        self == .providerReported
    }
}

enum AgentVerificationStatus: String, Codable, Hashable {
    case notStarted
    case running
    case passed
    case failed
    case unavailable

    var title: String {
        switch self {
        case .notStarted:
            "Not verified"
        case .running:
            "Verifying"
        case .passed:
            "Verified"
        case .failed:
            "Verification failed"
        case .unavailable:
            "Verification unavailable"
        }
    }
}

struct AgentVerification: Codable, Hashable {
    var status: AgentVerificationStatus
    var command: String?
    var output: String?
    var updatedAt: Date?

    static let notStarted = AgentVerification(status: .notStarted, command: nil, output: nil, updatedAt: nil)
}

struct AgentChangedFile: Identifiable, Codable, Hashable {
    let path: String
    let oldPath: String?
    let status: AgentChangedFileStatus
    let additions: Int?
    let deletions: Int?
    let isBinary: Bool

    var id: String { oldPath.map { "\($0)->\(path)" } ?? path }
}

struct AgentRunEvent: Identifiable, Codable, Hashable {
    let id: UUID
    let kind: AgentRunEventKind
    let label: String
    let text: String
    let timestamp: Date

    init(
        id: UUID = UUID(),
        kind: AgentRunEventKind,
        label: String,
        text: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.text = text
        self.timestamp = timestamp
    }
}

struct AgentRun: Identifiable, Codable, Hashable {
    let id: UUID
    let providerID: String
    var paneID: UUID?
    var projectID: UUID?
    var worktreeID: UUID?
    var worktreePath: String?
    var sessionID: String?
    var transcriptPath: String?
    var title: String
    var status: AgentRunStatus
    var sourceConfidence: AgentSourceConfidence
    var changedFiles: [AgentChangedFile]
    var changedFilesAttribution: AgentChangedFilesAttribution
    var verification: AgentVerification
    var startedAt: Date
    var lastEventAt: Date
    var events: [AgentRunEvent]
}
