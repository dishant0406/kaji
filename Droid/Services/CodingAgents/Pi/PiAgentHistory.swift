import Foundation

enum PiAgentHistory {
    static func options(
        projectPath: String?,
        query: String,
        limit: Int,
        env: [String: String],
        fileManager: FileManager
    ) -> [AskHistoryOption] {
        let root = sessionsRoot(env: env)
        let files = CodingAgentHistoryTools.recentFiles(
            under: root,
            extensions: ["jsonl"],
            maxFiles: query.isEmpty ? 200 : 500,
            fileManager: fileManager
        )
        let options = files.compactMap { url in
            metadata(url: url).map { metadata in
                AskHistoryOption(
                    provider: AskProvider(agentID: "pi"),
                    sessionID: metadata.id,
                    title: metadata.title,
                    detail: CodingAgentHistoryTools.detail(provider: AskProvider(agentID: "pi"), path: metadata.cwd),
                    projectPath: metadata.cwd,
                    updatedAt: metadata.updatedAt ?? CodingAgentHistoryTools.modifiedAt(url: url, fileManager: fileManager)
                )
            }
        }
        return CodingAgentHistoryTools.filter(options, projectPath: projectPath, query: query, limit: limit)
    }

    private static func sessionsRoot(env: [String: String]) -> URL {
        let base = env["PI_CODING_AGENT_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = if let base, !base.isEmpty {
            base
        } else {
            "\(env["HOME"] ?? NSHomeDirectory())/.pi/agent"
        }
        return URL(fileURLWithPath: path).appendingPathComponent("sessions", isDirectory: true)
    }

    private static func metadata(url: URL) -> CodingAgentHistoryTools.Metadata? {
        var id: String?
        var cwd: String?
        var title: String?
        var updatedAt: Date?

        for line in AskHistoryFilePrefix.lines(url: url) {
            guard let object = CodingAgentHistoryTools.jsonObject(line) else { continue }
            if object["type"] as? String == "session" {
                id = object["id"] as? String
                cwd = object["cwd"] as? String
                updatedAt = isoDate(object["timestamp"] as? String)
            }
            title = title ?? userText(from: object)
            if id != nil, title != nil { break }
        }

        guard let id else { return nil }
        return .init(
            id: id,
            cwd: cwd,
            title: CodingAgentHistoryTools.normalizedTitle(title, fallback: "Pi session"),
            updatedAt: updatedAt
        )
    }

    private static func userText(from object: [String: Any]) -> String? {
        guard object["type"] as? String == "message",
              let message = object["message"] as? [String: Any],
              message["role"] as? String == "user"
        else { return nil }
        if let text = message["content"] as? String { return text }
        return CodingAgentHistoryTools.messageText(from: message["content"])
    }

    private static func isoDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }
}
