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

    init(
        projects: [ParentAgentProjectContext]? = nil,
        activeProject: ParentAgentProjectContext? = nil,
        message: String? = nil,
        answer: String? = nil
    ) {
        self.projects = projects
        self.activeProject = activeProject
        self.message = message
        self.answer = answer
    }
}
