import Foundation

struct KajiAgentTaskToolDetails: Hashable {
    var progress: [KajiAgentSubagentProgress] = []
    var results: [KajiAgentSubagentResult] = []
    var asyncState: String?
    var jobID: String?

    init?(json: KajiAgentJSONValue?) {
        guard let object = json?.objectValue else { return nil }
        progress = object["progress"]?.arrayValue?.compactMap(KajiAgentSubagentProgress.init(json:)) ?? []
        results = object["results"]?.arrayValue?.compactMap(KajiAgentSubagentResult.init(json:)) ?? []
        if let asyncObject = object["async"]?.objectValue {
            asyncState = asyncObject["state"]?.stringValue
            jobID = asyncObject["jobId"]?.stringValue
        }
        guard !progress.isEmpty || !results.isEmpty || asyncState != nil else { return nil }
    }

    var visibleAgents: [KajiAgentSubagentProgress] {
        if !progress.isEmpty { return progress }
        return results.map(KajiAgentSubagentProgress.init(result:))
    }
}

struct KajiAgentSubagentProgress: Identifiable, Hashable {
    let id: String
    let index: Int
    let agent: String
    let status: String
    let task: String
    let assignment: String?
    let description: String?
    let currentTool: String?
    let currentToolArgs: String?
    let recentOutput: [String]
    let failureText: String?
    let toolCount: Int
    let tokens: Int
    let durationMs: Int
    let cost: Double
    let sessionFile: String?

    init?(json: KajiAgentJSONValue) {
        guard let object = json.objectValue,
              let id = object["id"]?.stringValue,
              let agent = object["agent"]?.stringValue,
              let status = object["status"]?.stringValue,
              let task = object["task"]?.stringValue
        else { return nil }
        self.id = id
        self.index = object["index"]?.numberValue.map(Int.init) ?? 0
        self.agent = agent
        self.status = status
        self.task = task
        self.assignment = object["assignment"]?.stringValue
        self.description = object["description"]?.stringValue
        self.currentTool = object["currentTool"]?.stringValue
        self.currentToolArgs = object["currentToolArgs"]?.stringValue
        self.recentOutput = object["recentOutput"]?.arrayValue?.compactMap(\.stringValue) ?? []
        self.failureText = object["failureText"]?.stringValue ?? object["error"]?.stringValue ?? object["stderr"]?.stringValue
        self.toolCount = object["toolCount"]?.numberValue.map(Int.init) ?? 0
        self.tokens = object["tokens"]?.numberValue.map(Int.init) ?? 0
        self.durationMs = object["durationMs"]?.numberValue.map(Int.init) ?? 0
        self.cost = object["cost"]?.numberValue ?? 0
        self.sessionFile = object["sessionFile"]?.stringValue
    }

    init(result: KajiAgentSubagentResult) {
        id = result.id
        index = result.index
        agent = result.agent
        status = result.exitCode == 0 ? "completed" : "failed"
        task = result.task
        assignment = result.assignment
        description = result.description
        currentTool = nil
        currentToolArgs = nil
        recentOutput = result.output.nilIfEmpty.map { [$0] } ?? []
        failureText = result.error ?? result.stderr.nilIfEmpty
        toolCount = 0
        tokens = result.tokens
        durationMs = result.durationMs
        cost = 0
        sessionFile = nil
    }
}

struct KajiAgentSubagentResult: Identifiable, Hashable {
    let id: String
    let index: Int
    let agent: String
    let task: String
    let assignment: String?
    let description: String?
    let exitCode: Int
    let output: String
    let stderr: String
    let error: String?
    let durationMs: Int
    let tokens: Int
    let outputPath: String?

    init?(json: KajiAgentJSONValue) {
        guard let object = json.objectValue,
              let id = object["id"]?.stringValue,
              let agent = object["agent"]?.stringValue,
              let task = object["task"]?.stringValue
        else { return nil }
        self.id = id
        self.index = object["index"]?.numberValue.map(Int.init) ?? 0
        self.agent = agent
        self.task = task
        self.assignment = object["assignment"]?.stringValue
        self.description = object["description"]?.stringValue
        self.exitCode = object["exitCode"]?.numberValue.map(Int.init) ?? 1
        self.output = object["output"]?.stringValue ?? ""
        self.stderr = object["stderr"]?.stringValue ?? ""
        self.error = object["error"]?.stringValue
        self.durationMs = object["durationMs"]?.numberValue.map(Int.init) ?? 0
        self.tokens = object["tokens"]?.numberValue.map(Int.init) ?? 0
        self.outputPath = object["outputPath"]?.stringValue
    }
}
