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
            databaseOptions(limit: limit, env: env, fileManager: fileManager) + legacyOptions(env: env, fileManager: fileManager)
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

    private static func databaseOptions(limit: Int, env: [String: String], fileManager: FileManager) -> [AskHistoryOption] {
        let databasePath = env["OPENCODE_DB_PATH"] ?? URL(fileURLWithPath: env["HOME"] ?? NSHomeDirectory())
            .appendingPathComponent(".local/share/opencode/opencode.db")
            .path
        guard fileManager.fileExists(atPath: databasePath) else { return [] }
        let configuredLimit = Int(env["OPENCODE_HISTORY_SCAN_LIMIT"] ?? "")
        let sessionLimit = max(1, min(500, configuredLimit ?? max(100, max(limit, 1) * 20)))
        let sql = """
        with recent as (
          select id, directory, title, time_updated
          from session
          where time_archived is null
          order by time_updated desc
          limit \(sessionLimit)
        ),
        first_prompt as (
          select session_id, prompt from (
            select
              m.session_id,
              substr(json_extract(p.data, '$.text'), 1, 500) as prompt,
              row_number() over (partition by m.session_id order by p.time_created) as row_number
            from recent r
            join message m on m.session_id = r.id
            join part p on p.message_id = m.id
            where r.title like 'New session - %'
              and json_extract(m.data, '$.role') = 'user'
              and json_extract(p.data, '$.type') = 'text'
              and coalesce(json_extract(p.data, '$.text'), '') <> ''
          )
          where row_number = 1
        )
        select
          recent.id,
          recent.directory,
          recent.title,
          recent.time_updated,
          first_prompt.prompt
        from recent
        left join first_prompt on first_prompt.session_id = recent.id
        """
        let fallbackSQL = """
        select id, directory, title, time_updated
        from session
        where time_archived is null
        order by time_updated desc
        limit \(sessionLimit)
        """
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
        DispatchQueue.global(qos: .userInitiated).sync {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
            process.arguments = ["-json", databasePath, sql]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            let finished = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in finished.signal() }

            do { try process.run() } catch { return nil }
            let timedOut = finished.wait(timeout: .now() + 3) == .timedOut
            if timedOut {
                process.terminate()
                process.waitUntilExit()
                return nil
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return process.terminationStatus == 0 ? data : nil
        }
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
