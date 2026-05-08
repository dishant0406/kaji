import Foundation

enum OpenCodeAgentHistory {
    private struct DatabaseRow: Decodable {
        let id: String
        let directory: String
        let title: String
        let prompt: String?
        let timeUpdated: TimeInterval

        private enum CodingKeys: String, CodingKey {
            case id
            case directory
            case title
            case prompt
            case timeUpdated = "time_updated"
        }
    }

    static func options(
        projectPath: String?,
        query: String,
        limit: Int,
        env: [String: String],
        fileManager: FileManager
    ) -> [AskHistoryOption] {
        let options = merged(
            databaseOptions(env: env, fileManager: fileManager) + legacyOptions(env: env, fileManager: fileManager)
        )
        return CodingAgentHistoryTools.filter(options, projectPath: projectPath, query: query, limit: limit)
    }

    private static func legacyOptions(env: [String: String], fileManager: FileManager) -> [AskHistoryOption] {
        let home = env["HOME"] ?? NSHomeDirectory()
        let root = URL(fileURLWithPath: home).appendingPathComponent(".local/share/opencode/storage/session", isDirectory: true)
        return CodingAgentHistoryTools.files(under: root, extensions: ["json"], fileManager: fileManager).compactMap { url in
            guard let metadata = metadata(url: url) else { return nil }
            return AskHistoryOption(
                provider: .opencode,
                sessionID: metadata.id,
                title: metadata.title,
                detail: CodingAgentHistoryTools.detail(provider: .opencode, path: metadata.cwd),
                projectPath: metadata.cwd,
                updatedAt: metadata.updatedAt ?? CodingAgentHistoryTools.modifiedAt(url: url, fileManager: fileManager)
            )
        }
    }

    private static func databaseOptions(env: [String: String], fileManager: FileManager) -> [AskHistoryOption] {
        let databasePath = env["OPENCODE_DB_PATH"] ?? URL(fileURLWithPath: env["HOME"] ?? NSHomeDirectory())
            .appendingPathComponent(".local/share/opencode/opencode.db")
            .path
        guard fileManager.fileExists(atPath: databasePath) else { return [] }
        let sql = """
        select
          s.id,
          s.directory,
          s.title,
          s.time_updated,
          (
            select json_extract(p.data, '$.text')
            from message m
            join part p on p.message_id = m.id
            where m.session_id = s.id
              and json_extract(m.data, '$.role') = 'user'
              and json_extract(p.data, '$.type') = 'text'
              and coalesce(json_extract(p.data, '$.text'), '') <> ''
            order by p.time_created
            limit 1
          ) as prompt
        from session s
        where s.time_archived is null
        order by s.time_updated desc
        """
        let fallbackSQL = "select id, directory, title, time_updated from session where time_archived is null order by time_updated desc"
        guard let data = runSQLite(databasePath: databasePath, sql: sql) ?? runSQLite(databasePath: databasePath, sql: fallbackSQL),
              let rows = try? JSONDecoder().decode([DatabaseRow].self, from: data)
        else { return [] }
        return rows.map { row in
            AskHistoryOption(
                provider: .opencode,
                sessionID: row.id,
                title: databaseTitle(row),
                detail: CodingAgentHistoryTools.detail(provider: .opencode, path: row.directory),
                projectPath: row.directory,
                updatedAt: Date(timeIntervalSince1970: row.timeUpdated / 1000)
            )
        }
    }

    private static func metadata(url: URL) -> CodingAgentHistoryTools.Metadata? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["id"] as? String
        else { return nil }
        let time = object["time"] as? [String: Any]
        let updated = (time?["updated"] as? TimeInterval).map { Date(timeIntervalSince1970: $0 / 1000) }
        return .init(
            id: id,
            cwd: object["directory"] as? String,
            title: CodingAgentHistoryTools.normalizedTitle(
                object["title"] as? String,
                fallback: "OpenCode session"
            ),
            updatedAt: updated
        )
    }

    private static func runSQLite(databasePath: String, sql: String) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-json", databasePath, sql]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }

    private static func databaseTitle(_ row: DatabaseRow) -> String {
        if row.title.hasPrefix("New session - ") {
            return CodingAgentHistoryTools.normalizedTitle(row.prompt, fallback: row.title)
        }
        return CodingAgentHistoryTools.normalizedTitle(row.title, fallback: "OpenCode session")
    }

    private static func merged(_ options: [AskHistoryOption]) -> [AskHistoryOption] {
        var seen = Set<String>()
        return options.filter { seen.insert($0.id).inserted }
    }
}
