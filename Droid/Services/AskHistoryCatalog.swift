import Foundation

enum AskHistoryCatalog {
    static func options(
        provider: AskProvider,
        projectPath: String?,
        query: String,
        limit: Int = 30,
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> [AskHistoryOption] {
        guard provider != .terminal,
              let agent = CodingAgentRegistry.shared.agent(id: provider.rawValue)
        else { return [] }
        return agent.historyOptions(
            projectPath: projectPath,
            query: query,
            limit: limit,
            env: env,
            fileManager: fileManager
        )
    }
}
