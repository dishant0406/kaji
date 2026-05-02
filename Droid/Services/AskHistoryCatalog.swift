import Foundation

enum AskHistoryCatalog {
    private struct HistoryMetadata {
        let id: String
        let cwd: String?
        let title: String
        let updatedAt: Date?
    }

    private struct OpenCodeDatabaseRow: Decodable {
        let id: String
        let directory: String
        let title: String
        let timeUpdated: TimeInterval

        private enum CodingKeys: String, CodingKey {
            case id
            case directory
            case title
            case timeUpdated = "time_updated"
        }
    }

    static func options(
        provider: AskProvider,
        projectPath: String?,
        query: String,
        limit: Int = 30,
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> [AskHistoryOption] {
        let options: [AskHistoryOption] = switch provider {
        case .codex:
            codexOptions(query: query, env: env, fileManager: fileManager)
        case .claude:
            claudeOptions(env: env, fileManager: fileManager)
        case .opencode:
            opencodeOptions(env: env, fileManager: fileManager)
        case .terminal:
            []
        }

        let normalizedQuery = query.lowercased()
        let normalizedProjectPath = projectPath.map(normalizedPath)
        return options
            .filter { option in
                guard normalizedProjectPath == nil || normalizedPath(option.projectPath) == normalizedProjectPath else { return false }
                return normalizedQuery.isEmpty || option.title.lowercased().contains(normalizedQuery) ||
                    option.sessionID.lowercased().contains(normalizedQuery)
            }
            .sorted { lhs, rhs in
                lhs.updatedAt > rhs.updatedAt
            }
            .prefix(limit)
            .map(\.self)
    }

    private static func codexOptions(query: String, env: [String: String], fileManager: FileManager) -> [AskHistoryOption] {
        let root = CodexSessionPathResolver.sessionsRootURL(env: env)
        let maxFiles = query.isEmpty ? 160 : 400
        return recentFiles(under: root, extensions: ["jsonl"], maxFiles: maxFiles, fileManager: fileManager).compactMap { url in
            guard let metadata = codexMetadata(url: url) else { return nil }
            return .init(
                provider: .codex,
                sessionID: metadata.id,
                title: metadata.title,
                detail: detail(provider: .codex, path: metadata.cwd),
                projectPath: metadata.cwd,
                updatedAt: modifiedAt(url: url, fileManager: fileManager)
            )
        }
    }

    private static func claudeOptions(env: [String: String], fileManager: FileManager) -> [AskHistoryOption] {
        let home = env["HOME"] ?? NSHomeDirectory()
        let root = URL(fileURLWithPath: home).appendingPathComponent(".claude/projects", isDirectory: true)
        return files(under: root, extensions: ["jsonl"], fileManager: fileManager).compactMap { url in
            guard let metadata = claudeMetadata(url: url) else { return nil }
            return .init(
                provider: .claude,
                sessionID: metadata.id,
                title: metadata.title,
                detail: detail(provider: .claude, path: metadata.cwd),
                projectPath: metadata.cwd,
                updatedAt: modifiedAt(url: url, fileManager: fileManager)
            )
        }
    }

    private static func opencodeOptions(env: [String: String], fileManager: FileManager) -> [AskHistoryOption] {
        let databaseOptions = opencodeDatabaseOptions(env: env, fileManager: fileManager)
        let home = env["HOME"] ?? NSHomeDirectory()
        let root = URL(fileURLWithPath: home).appendingPathComponent(".local/share/opencode/storage/session", isDirectory: true)
        let legacyOptions: [AskHistoryOption] = files(under: root, extensions: ["json"], fileManager: fileManager).compactMap { url in
            guard let metadata = opencodeMetadata(url: url) else { return nil }
            return AskHistoryOption(
                provider: .opencode,
                sessionID: metadata.id,
                title: metadata.title,
                detail: detail(provider: .opencode, path: metadata.cwd),
                projectPath: metadata.cwd,
                updatedAt: metadata.updatedAt ?? modifiedAt(url: url, fileManager: fileManager)
            )
        }
        return mergedOptions(databaseOptions + legacyOptions)
    }

    private static func opencodeDatabaseOptions(env: [String: String], fileManager: FileManager) -> [AskHistoryOption] {
        let databasePath = env["OPENCODE_DB_PATH"] ?? URL(fileURLWithPath: env["HOME"] ?? NSHomeDirectory())
            .appendingPathComponent(".local/share/opencode/opencode.db")
            .path
        guard fileManager.fileExists(atPath: databasePath) else { return [] }
        let sql = "select id, directory, title, time_updated from session where time_archived is null order by time_updated desc"
        guard let data = runSQLite(databasePath: databasePath, sql: sql),
              let rows = try? JSONDecoder().decode([OpenCodeDatabaseRow].self, from: data)
        else { return [] }
        return rows.map { row in
            AskHistoryOption(
                provider: .opencode,
                sessionID: row.id,
                title: normalizedTitle(row.title, fallback: "OpenCode session"),
                detail: detail(provider: .opencode, path: row.directory),
                projectPath: row.directory,
                updatedAt: Date(timeIntervalSince1970: row.timeUpdated / 1000)
            )
        }
    }

    private static func runSQLite(databasePath: String, sql: String) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-json", databasePath, sql]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }

    private static func mergedOptions(_ options: [AskHistoryOption]) -> [AskHistoryOption] {
        var seen = Set<String>()
        return options.filter { option in
            guard !seen.contains(option.id) else { return false }
            seen.insert(option.id)
            return true
        }
    }

    private static func files(under root: URL, extensions: Set<String>, fileManager: FileManager) -> [URL] {
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        return enumerator.compactMap { item in
            guard let url = item as? URL, extensions.contains(url.pathExtension) else { return nil }
            return url
        }
    }

    private static func recentFiles(
        under root: URL,
        extensions: Set<String>,
        maxFiles: Int,
        fileManager: FileManager
    ) -> [URL] {
        var results: [URL] = []
        var pending = [root]
        while let directory = pending.popLast(), results.count < maxFiles {
            let children = (try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            let sorted = children.sorted { lhs, rhs in lhs.lastPathComponent > rhs.lastPathComponent }
            var directories: [URL] = []
            for url in sorted where results.count < maxFiles {
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
                if values?.isDirectory == true {
                    directories.append(url)
                } else if values?.isRegularFile == true, extensions.contains(url.pathExtension) {
                    results.append(url)
                }
            }
            pending.append(contentsOf: directories.reversed())
        }
        return results
    }

    private static func codexMetadata(url: URL) -> HistoryMetadata? {
        var id: String?
        var cwd: String?
        var title: String?
        for line in AskHistoryFilePrefix.lines(url: url) {
            guard let object = jsonObject(line) else { continue }
            if object["type"] as? String == "session_meta", let payload = object["payload"] as? [String: Any] {
                id = payload["id"] as? String
                cwd = payload["cwd"] as? String
            }
            title = title ?? userText(from: object)
            if id != nil, title != nil { break }
        }
        guard let id else { return nil }
        return .init(id: id, cwd: cwd, title: normalizedTitle(title, fallback: "Codex session"), updatedAt: nil)
    }

    private static func claudeMetadata(url: URL) -> HistoryMetadata? {
        var id = url.deletingPathExtension().lastPathComponent
        var cwd: String?
        var title: String?
        for line in AskHistoryFilePrefix.lines(url: url) {
            guard let object = jsonObject(line) else { continue }
            id = object["sessionId"] as? String ?? id
            cwd = object["cwd"] as? String ?? cwd
            title = title ?? claudeUserText(from: object)
            if title != nil, cwd != nil { break }
        }
        return .init(id: id, cwd: cwd, title: normalizedTitle(title, fallback: "Claude session"), updatedAt: nil)
    }

    private static func opencodeMetadata(url: URL) -> HistoryMetadata? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["id"] as? String
        else { return nil }
        let time = object["time"] as? [String: Any]
        let updated = (time?["updated"] as? TimeInterval).map { Date(timeIntervalSince1970: $0 / 1000) }
        return .init(
            id: id,
            cwd: object["directory"] as? String,
            title: normalizedTitle(object["title"] as? String, fallback: "OpenCode session"),
            updatedAt: updated
        )
    }

    private static func userText(from object: [String: Any]) -> String? {
        guard let payload = object["payload"] as? [String: Any], payload["role"] as? String == "user" else { return nil }
        return messageText(from: payload["content"])
    }

    private static func claudeUserText(from object: [String: Any]) -> String? {
        guard object["type"] as? String == "user", let message = object["message"] as? [String: Any] else { return nil }
        if let text = message["content"] as? String { return text }
        return messageText(from: message["content"])
    }

    private static func messageText(from content: Any?) -> String? {
        guard let items = content as? [[String: Any]] else { return nil }
        return items.compactMap { $0["text"] as? String }.joined(separator: " ")
    }

    private static func jsonObject(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func modifiedAt(url: URL, fileManager: FileManager) -> Date {
        (try? fileManager.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? .distantPast
    }

    private static func detail(provider: AskProvider, path: String?) -> String {
        let name = path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Unknown project"
        return "\(provider.title) in \(name)"
    }

    private static func normalizedPath(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func normalizedTitle(_ title: String?, fallback: String) -> String {
        let cleaned = (title ?? "").replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? fallback : String(cleaned.prefix(80))
    }
}
