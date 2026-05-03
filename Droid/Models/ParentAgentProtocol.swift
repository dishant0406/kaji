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
        self.projects = projects
        self.result = result
    }
}

struct ParentAgentToolResult: Codable {
    var projects: [ParentAgentProjectContext]?
    var activeProject: ParentAgentProjectContext?
    var message: String?
    var answer: String?
    var childRun: ParentAgentChildRunContext?
    var childRuns: [ParentAgentChildRunContext]?
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
        self.worktree = worktree
        self.changedFiles = changedFiles
        self.verification = verification
        self.codingProviders = codingProviders
    }
}

struct ParentAgentChildRunContext: Codable, Hashable {
    let id: String
    let provider: String
    let project: String
    let status: String
    let title: String
    let lastEvent: String?
    let recentEvents: [String]?
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
