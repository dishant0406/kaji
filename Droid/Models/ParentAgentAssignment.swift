import Foundation

enum ParentAgentAssignmentStatus: String, Codable, Hashable {
    case planned
    case blocked
    case requiresIsolation
    case choosingAgent
    case queued
    case running
    case waitingForUser
    case completed
    case incomplete
    case failed
    case stopped
    case stale

    var canContinue: Bool {
        self == .running || self == .waitingForUser
    }

    var canReplace: Bool {
        self == .incomplete || self == .failed || self == .stopped || self == .stale
    }

    var blocksProviderSelection: Bool {
        self == .running || self == .waitingForUser || self == .queued || self == .choosingAgent
    }
}

enum ParentAgentAssignmentMode: String, Codable, Hashable {
    case fresh
    case continuation
    case replacement
}

enum ParentAgentAssignmentIsolation: String, Codable, Hashable {
    case sharedWorktree
    case isolatedWorktree
    case readOnly
}

enum ParentAgentAssignmentNextAction: String, Codable, Hashable {
    case chooseAgent
    case continueRun
    case approveInTerminal
    case waitForAssignment
    case useIsolatedWorktree
    case replaceAssignment
    case inspectResult
}

struct ParentAgentAssignment: Identifiable, Codable, Hashable {
    let id: UUID
    let parentTaskID: UUID
    var title: String
    var prompt: String
    var projectID: UUID?
    var projectName: String?
    var worktreeID: UUID?
    var worktreeName: String?
    var worktreePath: String?
    var providerID: String?
    var modelID: String?
    var runID: UUID?
    var paneID: UUID?
    var status: ParentAgentAssignmentStatus
    var mode: ParentAgentAssignmentMode
    var isolation: ParentAgentAssignmentIsolation
    var finalSummary: String?
    var changedFiles: [ParentAgentChangedFileContext]
    var verification: ParentAgentVerificationContext?
    var attention: ParentAgentAttention?
    var blockerReason: String?
    var nextAction: ParentAgentAssignmentNextAction?
    var lastEvent: String?
    var recentEvents: [String]
    var createdAt: Date
    var updatedAt: Date

    init(
        parentTaskID: UUID,
        title: String,
        prompt: String,
        project: Project,
        worktree: Worktree,
        mode: ParentAgentAssignmentMode = .fresh,
        isolation: ParentAgentAssignmentIsolation = .sharedWorktree
    ) {
        self.id = UUID()
        self.parentTaskID = parentTaskID
        self.title = title
        self.prompt = prompt
        self.projectID = project.id
        self.projectName = project.name
        self.worktreeID = worktree.id
        self.worktreeName = worktree.name
        self.worktreePath = worktree.path
        self.status = .planned
        self.mode = mode
        self.isolation = isolation
        self.changedFiles = []
        self.recentEvents = []
        self.createdAt = Date()
        self.updatedAt = createdAt
    }
}

struct ParentAgentAssignmentRunAttachment {
    let runID: UUID
    let paneID: UUID?
    let providerID: String
    let modelID: String
}

struct ParentAgentAssignmentCompletion {
    let summary: String?
    let changedFiles: [ParentAgentChangedFileContext]
    let verification: ParentAgentVerificationContext?
    let status: ParentAgentAssignmentStatus
}
