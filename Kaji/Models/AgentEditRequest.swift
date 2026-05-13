import Foundation

struct AgentEditRequest: Sendable {
    let filePath: String
    let projectPath: String
    let selectedText: String
    let instruction: String
    let provider: AskProvider
    let languageID: String?
    let model: String?
}

struct AgentEditResponse: Sendable {
    let replacement: String
    let providerID: String
}
