import Foundation

enum ClaudeCodeAgentHistory {
    static func options(
        projectPath: String?,
        query: String,
        limit: Int,
        env: [String: String],
        fileManager: FileManager
    ) -> [AskHistoryOption] {
        let home = env["HOME"] ?? NSHomeDirectory()
        let root = URL(fileURLWithPath: home).appendingPathComponent(".claude/projects", isDirectory: true)
        let options = CodingAgentHistoryTools.files(under: root, extensions: ["jsonl"], fileManager: fileManager).map { url in
            let metadata = metadata(url: url)
            return AskHistoryOption(
                provider: .claude,
                sessionID: metadata.id,
                title: metadata.title,
                detail: CodingAgentHistoryTools.detail(provider: .claude, path: metadata.cwd),
                projectPath: metadata.cwd,
                updatedAt: CodingAgentHistoryTools.modifiedAt(url: url, fileManager: fileManager)
            )
        }
        return CodingAgentHistoryTools.filter(options, projectPath: projectPath, query: query, limit: limit)
    }

    private static func metadata(url: URL) -> CodingAgentHistoryTools.Metadata {
        var id = url.deletingPathExtension().lastPathComponent
        var cwd: String?
        var title: String?
        for line in AskHistoryFilePrefix.lines(url: url) {
            guard let object = CodingAgentHistoryTools.jsonObject(line) else { continue }
            id = object["sessionId"] as? String ?? id
            cwd = object["cwd"] as? String ?? cwd
            title = title ?? userText(from: object)
            if title != nil, cwd != nil { break }
        }
        return .init(id: id, cwd: cwd, title: CodingAgentHistoryTools.normalizedTitle(title, fallback: "Claude session"), updatedAt: nil)
    }

    private static func userText(from object: [String: Any]) -> String? {
        guard object["type"] as? String == "user", let message = object["message"] as? [String: Any] else { return nil }
        if let text = message["content"] as? String { return text }
        return CodingAgentHistoryTools.messageText(from: message["content"])
    }
}
