import Foundation

enum AskSkillCatalog {
    static func options(
        provider: AskProvider,
        projectPath: String?,
        query: String,
        limit: Int = 40,
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> [AskSkillOption] {
        let normalizedQuery = query.lowercased()
        var seen: Set<String> = []
        return roots(provider: provider, projectPath: projectPath, env: env)
            .flatMap { root in skillDirectories(root: root.url, source: root.source, fileManager: fileManager) }
            .filter { option in
                guard !seen.contains(option.name) else { return false }
                seen.insert(option.name)
                return normalizedQuery.isEmpty || option.name.lowercased().contains(normalizedQuery) ||
                    option.title.lowercased().contains(normalizedQuery)
            }
            .prefix(limit)
            .map(\.self)
    }

    private static func roots(provider: AskProvider, projectPath: String?, env: [String: String]) -> [(url: URL, source: String)] {
        guard provider != .terminal else { return [] }
        let home = env["HOME"] ?? NSHomeDirectory()
        let definition = provider.definition
        var roots: [(URL, String)] = []
        if let projectPath {
            for directory in definition?.projectSkillDirectories ?? [".agents/skills"] {
                roots.append((URL(fileURLWithPath: projectPath).appendingPathComponent(directory, isDirectory: true), "Project"))
            }
        }
        roots.append((URL(fileURLWithPath: home).appendingPathComponent(".agents/skills", isDirectory: true), "Agents"))
        for directory in definition?.homeSkillDirectories ?? [] {
            roots.append((URL(fileURLWithPath: home).appendingPathComponent(directory, isDirectory: true), provider.title))
        }
        return roots
    }

    private static func skillDirectories(root: URL, source: String, fileManager: FileManager) -> [AskSkillOption] {
        guard let items = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        return items.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            let skillFile = url.appendingPathComponent("SKILL.md")
            guard fileManager.fileExists(atPath: skillFile.path) else { return nil }
            let name = url.lastPathComponent
            let title = title(from: skillFile) ?? name
            return AskSkillOption(name: name, title: title, detail: "\(source) skill", path: skillFile.path, source: source)
        }
        .sorted { $0.name < $1.name }
    }

    private static func title(from url: URL) -> String? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for line in content.components(separatedBy: .newlines).prefix(30) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("description:") {
                return String(trimmed.dropFirst("description:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if trimmed.hasPrefix("# ") {
                return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }
}
