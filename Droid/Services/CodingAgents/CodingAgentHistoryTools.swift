import Foundation

enum CodingAgentHistoryTools {
    struct Metadata {
        let id: String
        let cwd: String?
        let title: String
        let updatedAt: Date?
    }

    static func filter(
        _ options: [AskHistoryOption],
        projectPath: String?,
        query: String,
        limit: Int
    ) -> [AskHistoryOption] {
        let normalizedQuery = query.lowercased()
        let normalizedProjectPath = projectPath.map(normalizedPath)
        return options
            .filter { option in
                guard normalizedProjectPath == nil || normalizedPath(option.projectPath) == normalizedProjectPath else { return false }
                return normalizedQuery.isEmpty ||
                    option.title.lowercased().contains(normalizedQuery) ||
                    option.sessionID.lowercased().contains(normalizedQuery)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .map(\.self)
    }

    static func files(under root: URL, extensions: Set<String>, fileManager: FileManager) -> [URL] {
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        return enumerator.compactMap { item in
            guard let url = item as? URL, extensions.contains(url.pathExtension) else { return nil }
            return url
        }
    }

    static func recentFiles(
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
            let sorted = children.sorted { $0.lastPathComponent > $1.lastPathComponent }
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

    static func detail(provider: AskProvider, path: String?) -> String {
        let name = path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Unknown project"
        return "\(provider.title) in \(name)"
    }

    static func normalizedTitle(_ title: String?, fallback: String) -> String {
        let cleaned = (title ?? "").replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? fallback : String(cleaned.prefix(80))
    }

    static func modifiedAt(url: URL, fileManager: FileManager) -> Date {
        (try? fileManager.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? .distantPast
    }

    static func jsonObject(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func messageText(from content: Any?) -> String? {
        guard let items = content as? [[String: Any]] else { return nil }
        return items.compactMap { $0["text"] as? String }.joined(separator: " ")
    }

    private static func normalizedPath(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
