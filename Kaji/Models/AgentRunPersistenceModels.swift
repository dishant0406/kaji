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
