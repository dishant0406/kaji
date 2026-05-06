import Foundation

enum AgentInstructionDiscovery {
    private static let skippedDirectories = Set([
        ".build", ".git", ".swiftpm", "DerivedData", "node_modules", "Pods", "vendor", "Vendor",
    ])

    static func discover(
        projectPath: String,
        definitions: [CodingAgentDefinition],
        homeDirectory: String = NSHomeDirectory(),
        fileManager: FileManager = .default
    ) -> [AgentInstructionGroup] {
        definitions.map { definition in
            AgentInstructionGroup(
                id: definition.id,
                displayName: definition.displayName,
                iconName: definition.iconName,
                documents: documents(
                    for: definition,
                    projectPath: projectPath,
                    homeDirectory: homeDirectory,
                    fileManager: fileManager
                )
            )
        }
    }

    private static func documents(
        for definition: CodingAgentDefinition,
        projectPath: String,
        homeDirectory: String,
        fileManager: FileManager
    ) -> [AgentInstructionDocument] {
        let globals = globalDocuments(for: definition, homeDirectory: homeDirectory, fileManager: fileManager)
        let project = projectDocuments(for: definition, projectPath: projectPath, fileManager: fileManager)
        return globals + project
    }

    private static func globalDocuments(
        for definition: CodingAgentDefinition,
        homeDirectory: String,
        fileManager: FileManager
    ) -> [AgentInstructionDocument] {
        definition.globalInstructionFiles.compactMap { relativePath in
            let path = (homeDirectory as NSString).appendingPathComponent(relativePath)
            return document(
                agentID: definition.id,
                scope: .global,
                path: path,
                displayPath: "~/\(relativePath)",
                fileManager: fileManager
            )
        }
    }

    private static func projectDocuments(
        for definition: CodingAgentDefinition,
        projectPath: String,
        fileManager: FileManager
    ) -> [AgentInstructionDocument] {
        let names = Set(definition.projectInstructionFiles)
        guard !names.isEmpty else { return [] }
        return projectInstructionPaths(projectPath: projectPath, names: names, fileManager: fileManager).compactMap { path in
            let relativePath = relativePath(path: path, root: projectPath)
            return document(
                agentID: definition.id,
                scope: relativePath.contains("/") ? .nested : .project,
                path: path,
                displayPath: relativePath,
                fileManager: fileManager
            )
        }
    }

    private static func projectInstructionPaths(
        projectPath: String,
        names: Set<String>,
        fileManager: FileManager
    ) -> [String] {
        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: projectPath),
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var paths: [String] = []
        for case let url as URL in enumerator {
            if shouldSkip(url: url, enumerator: enumerator) { continue }
            guard names.contains(url.lastPathComponent), isRegularFile(url: url) else { continue }
            paths.append(url.path)
        }
        return paths.sorted { sortKey(path: $0, root: projectPath) < sortKey(path: $1, root: projectPath) }
    }

    private static func shouldSkip(url: URL, enumerator: FileManager.DirectoryEnumerator) -> Bool {
        guard isDirectory(url: url) else { return false }
        if skippedDirectories.contains(url.lastPathComponent) {
            enumerator.skipDescendants()
            return true
        }
        return false
    }

    private static func document(
        agentID: String,
        scope: AgentInstructionScope,
        path: String,
        displayPath: String,
        fileManager: FileManager
    ) -> AgentInstructionDocument? {
        guard fileManager.fileExists(atPath: path),
              let content = try? String(contentsOfFile: path, encoding: .utf8)
        else { return nil }
        return AgentInstructionDocument(
            id: "\(agentID):\(path)",
            agentID: agentID,
            scope: scope,
            title: (path as NSString).lastPathComponent,
            displayPath: displayPath,
            path: path,
            content: content
        )
    }

    private static func relativePath(path: String, root: String) -> String {
        let rootURL = URL(fileURLWithPath: root).standardizedFileURL
        let pathURL = URL(fileURLWithPath: path).standardizedFileURL
        let rootComponents = rootURL.pathComponents
        let pathComponents = pathURL.pathComponents
        guard pathComponents.starts(with: rootComponents) else { return path }
        return pathComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }

    private static func sortKey(path: String, root: String) -> String {
        let relative = relativePath(path: path, root: root)
        let depth = relative.split(separator: "/").count
        return String(format: "%04d:%@", depth, relative)
    }

    private static func isDirectory(url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private static func isRegularFile(url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }
}
