import Foundation

struct ParentAgentEnvelope: Codable {
    var type: String
    var taskID: String?
    var prompt: String?
    var event: String?
    var message: String?
    var id: String?
    var name: String?
    var arguments: [String: String]?
    var ok: Bool?
    var attachments: [ParentAgentAttachmentContext]?
    var projects: [ParentAgentProjectContext]?
    var result: ParentAgentToolResult?

    init(
        type: String,
        taskID: String? = nil,
        prompt: String? = nil,
        event: String? = nil,
        message: String? = nil,
        id: String? = nil,
        name: String? = nil,
        arguments: [String: String]? = nil,
        ok: Bool? = nil,
        attachments: [ParentAgentAttachmentContext]? = nil,
        projects: [ParentAgentProjectContext]? = nil,
        result: ParentAgentToolResult? = nil
    ) {
        self.type = type
        self.taskID = taskID
        self.prompt = prompt
        self.event = event
        self.message = message
        self.id = id
        self.name = name
        self.arguments = arguments
        self.ok = ok
        self.attachments = attachments
        self.projects = projects
        self.result = result
    }
}

struct ParentAgentAttachmentContext: Codable, Hashable {
    let name: String
    let path: String
    let kind: String
    let mimeType: String
    let data: String?
}

struct ParentAgentToolResult: Codable {
    var projects: [ParentAgentProjectContext]?
    var activeProject: ParentAgentProjectContext?
    var message: String?
    var answer: String?
    var childRun: ParentAgentChildRunContext?
    var childRuns: [ParentAgentChildRunContext]?
    var assignment: ParentAgentAssignmentContext?
    var assignments: [ParentAgentAssignmentContext]?
    var worktree: ParentAgentWorktreeContext?
    var changedFiles: [ParentAgentChangedFileContext]?
    var verification: ParentAgentVerificationContext?
    var codingProviders: [ParentAgentCodingProviderContext]?

    init(
        projects: [ParentAgentProjectContext]? = nil,
        activeProject: ParentAgentProjectContext? = nil,
        message: String? = nil,
        answer: String? = nil,
        childRun: ParentAgentChildRunContext? = nil,
        childRuns: [ParentAgentChildRunContext]? = nil,
        assignment: ParentAgentAssignmentContext? = nil,
        assignments: [ParentAgentAssignmentContext]? = nil,
        worktree: ParentAgentWorktreeContext? = nil,
        changedFiles: [ParentAgentChangedFileContext]? = nil,
        verification: ParentAgentVerificationContext? = nil,
        codingProviders: [ParentAgentCodingProviderContext]? = nil
    ) {
        self.projects = projects
        self.activeProject = activeProject
        self.message = message
        self.answer = answer
        self.childRun = childRun
        self.childRuns = childRuns
        self.assignment = assignment
        self.assignments = assignments
        self.worktree = worktree
        self.changedFiles = changedFiles
        self.verification = verification
        self.codingProviders = codingProviders
    }
}

struct ParentAgentAssignmentContext: Codable, Hashable {
    let id: String
    let title: String
    let prompt: String
    let project: String?
    let worktree: String?
    let provider: String?
    let model: String?
    let runID: String?
    let status: String
    let mode: String
    let isolation: String
    let lastEvent: String?
    let recentEvents: [String]
    let finalSummary: String?
    let terminalOutput: String?
    let changedFiles: [ParentAgentChangedFileContext]
    let verification: ParentAgentVerificationContext?
    let attention: ParentAgentAttention?
    let blockerReason: String?
    let nextAction: String?
}

struct ParentAgentChildRunContext: Codable, Hashable {
    let id: String
    let provider: String
    let project: String
    let status: String
    let title: String
    let lastEvent: String?
    let recentEvents: [String]?
    let terminalOutput: String?
}

struct ParentAgentChangedFileContext: Codable, Hashable {
    let path: String
    let oldPath: String?
    let status: String
    let additions: Int?
    let deletions: Int?
    let isBinary: Bool
}

struct ParentAgentVerificationContext: Codable, Hashable {
    let status: String
    let command: String?
    let output: String?
}

struct ParentAgentCodingProviderContext: Codable, Hashable {
    let id: String
    let title: String
    let installed: Bool
    let enabled: Bool
    let models: [String]
    let defaultModel: String?
}
