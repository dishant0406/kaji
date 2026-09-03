import Foundation

enum AgentInstructionDiscovery {
    private static let fallbackIgnore = WorkspaceIgnoreClassifier()

    static func discover(
        projectPath: String,
        definitions: [CodingAgentDefinition],
        homeDirectory: String = NSHomeDirectory(),
        fileManager: FileManager = .default
    ) -> [AgentInstructionGroup] {
        discover(
            projectPath: projectPath,
            descriptors: definitions.map(AgentInstructionAgentDescriptor.init),
            homeDirectory: homeDirectory,
            fileManager: fileManager
        )
    }

    static func discover(
        projectPath: String,
        descriptors: [AgentInstructionAgentDescriptor],
        homeDirectory: String = NSHomeDirectory(),
        fileManager: FileManager = .default
    ) -> [AgentInstructionGroup] {
        descriptors.map { descriptor in
            AgentInstructionGroup(
                id: descriptor.id,
                displayName: descriptor.displayName,
                iconName: descriptor.iconName,
                documents: documents(
                    for: descriptor,
                    projectPath: projectPath,
                    homeDirectory: homeDirectory,
                    fileManager: fileManager
                )
            )
        }
    }

    private static func documents(
        for descriptor: AgentInstructionAgentDescriptor,
        projectPath: String,
        homeDirectory: String,
        fileManager: FileManager
    ) -> [AgentInstructionDocument] {
        let globals = globalDocuments(for: descriptor, homeDirectory: homeDirectory, fileManager: fileManager)
        let project = projectDocuments(for: descriptor, projectPath: projectPath, fileManager: fileManager)
        return globals + project
    }

    private static func globalDocuments(
        for descriptor: AgentInstructionAgentDescriptor,
        homeDirectory: String,
        fileManager: FileManager
    ) -> [AgentInstructionDocument] {
        descriptor.globalInstructionFiles.compactMap { relativePath in
            let path = (homeDirectory as NSString).appendingPathComponent(relativePath)
            return document(
                agentID: descriptor.id,
                scope: .global,
                path: path,
                displayPath: "~/\(relativePath)",
                fileManager: fileManager
            )
        }
    }

    private static func projectDocuments(
        for descriptor: AgentInstructionAgentDescriptor,
        projectPath: String,
        fileManager: FileManager
    ) -> [AgentInstructionDocument] {
        let names = Set(descriptor.projectInstructionFiles)
        guard !names.isEmpty else { return [] }
        return projectInstructionPaths(projectPath: projectPath, names: names, fileManager: fileManager).compactMap { path in
            let relativePath = relativePath(path: path, root: projectPath)
            return document(
                agentID: descriptor.id,
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
        if let paths = gitInstructionPaths(projectPath: projectPath, names: names, fileManager: fileManager) {
            return paths
        }
        return filesystemInstructionPaths(projectPath: projectPath, names: names, fileManager: fileManager)
    }

    private static func gitInstructionPaths(
        projectPath: String,
        names: Set<String>,
        fileManager: FileManager
    ) -> [String]? {
        guard let paths = GitFileListProvider.filePathsSync(repoPath: projectPath) else { return nil }
        return paths.compactMap { relativePath in
            guard names.contains((relativePath as NSString).lastPathComponent) else { return nil }
            let path = (projectPath as NSString).appendingPathComponent(relativePath)
            guard fileManager.fileExists(atPath: path), !isSymbolicLink(url: URL(fileURLWithPath: path)) else { return nil }
            return path
        }.sorted { sortKey(path: $0, root: projectPath) < sortKey(path: $1, root: projectPath) }
    }

    private static func filesystemInstructionPaths(
        projectPath: String,
        names: Set<String>,
        fileManager: FileManager
    ) -> [String] {
        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: projectPath),
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        else { return [] }

        var paths: [String] = []
        for case let url as URL in enumerator {
            if shouldSkip(url: url, enumerator: enumerator) {
                continue
            }
            guard names.contains(url.lastPathComponent), isRegularFile(url: url) else { continue }
            paths.append(url.path)
        }
        return paths.sorted { sortKey(path: $0, root: projectPath) < sortKey(path: $1, root: projectPath) }
    }

    private static func shouldSkip(url: URL, enumerator: FileManager.DirectoryEnumerator) -> Bool {
        if isSymbolicLink(url: url) {
            enumerator.skipDescendants()
            return true
        }
        guard isDirectory(url: url) else { return false }
        if fallbackIgnore.shouldSkipDirectoryName(url.lastPathComponent) {
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

    private static func isSymbolicLink(url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }
}
