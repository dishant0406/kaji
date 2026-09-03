import Foundation

enum CodexAgentHistory {
    static func options(
        projectPath: String?,
        query: String,
        limit: Int,
        env: [String: String],
        fileManager: FileManager
    ) -> [AskHistoryOption] {
        let root = CodexSessionPathResolver.sessionsRootURL(env: env)
        let maxFiles = query.isEmpty ? 160 : 400
        let files = CodingAgentHistoryTools.recentFiles(
            under: root,
            extensions: ["jsonl"],
            maxFiles: maxFiles,
            fileManager: fileManager
        )
        let options = files.compactMap { url in
            metadata(url: url).map { metadata in
                AskHistoryOption(
                    provider: .codex,
                    sessionID: metadata.id,
                    title: metadata.title,
                    detail: CodingAgentHistoryTools.detail(provider: .codex, path: metadata.cwd),
                    projectPath: metadata.cwd,
                    updatedAt: CodingAgentHistoryTools.modifiedAt(url: url, fileManager: fileManager)
                )
            }
        }
        return CodingAgentHistoryTools.filter(options, projectPath: projectPath, query: query, limit: limit)
    }

    private static func metadata(url: URL) -> CodingAgentHistoryTools.Metadata? {
        var id: String?
        var cwd: String?
        var title: String?
        for line in AskHistoryFilePrefix.lines(url: url) {
            guard let object = CodingAgentHistoryTools.jsonObject(line) else { continue }
            if object["type"] as? String == "session_meta", let payload = object["payload"] as? [String: Any] {
                id = payload["id"] as? String
                cwd = payload["cwd"] as? String
            }
            title = title ?? userText(from: object)
            if id != nil, title != nil {
                break
            }
        }
        guard let id else { return nil }
        return .init(id: id, cwd: cwd, title: CodingAgentHistoryTools.normalizedTitle(title, fallback: "Codex session"), updatedAt: nil)
    }

    private static func userText(from object: [String: Any]) -> String? {
        guard let payload = object["payload"] as? [String: Any], payload["role"] as? String == "user" else { return nil }
        guard let text = CodingAgentHistoryTools.messageText(from: payload["content"]), !isInjectedUserText(text) else { return nil }
        return text
    }

    private static func isInjectedUserText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("# AGENTS.md instructions for ") || trimmed.hasPrefix("<environment_context>")
    }
}
