import Foundation

enum FileSearchScanner {
    private static let catalog = WorkspaceIgnoreCatalog.bundled

    private static let rgURL = URL(fileURLWithPath: "/opt/homebrew/bin/rg")
    private static let findURL = URL(fileURLWithPath: "/usr/bin/find")

    static func scanAll(in projectPath: String, limit: Int) async -> [FileSearchResult] {
        if let paths = await GitFileListProvider.filePaths(repoPath: projectPath) {
            return results(from: paths, projectPath: projectPath, limit: limit)
        }
        if FileManager.default.isExecutableFile(atPath: rgURL.path) {
            return await runRipgrep(in: projectPath, glob: nil, limit: limit)
        }
        return await runFind(
            arguments: fullArguments(projectPath: projectPath),
            projectPath: projectPath,
            limit: limit
        )
    }

    static func scanShallow(in projectPath: String, maxDepth: Int, limit: Int) async -> [FileSearchResult] {
        if let paths = await GitFileListProvider.filePaths(repoPath: projectPath) {
            let scoped = paths.filter { $0.split(separator: "/").count <= maxDepth }
            return results(from: scoped, projectPath: projectPath, limit: limit)
        }
        return await runFind(
            arguments: initialArguments(projectPath: projectPath, maxDepth: maxDepth),
            projectPath: projectPath,
            limit: limit
        )
    }

    private static func runRipgrep(in projectPath: String, glob: String?, limit: Int?) async -> [FileSearchResult] {
        var arguments = ["--files", "--hidden"]
        appendPruneGlobs(into: &arguments)
        if let glob {
            arguments.append(contentsOf: ["--glob", glob])
        }
        return await FileSearchProcessRunner.collect(.init(
            executableURL: rgURL,
            arguments: arguments,
            projectPath: projectPath,
            currentDirectoryPath: projectPath,
            limit: limit,
            outputPathsAreRelative: true
        ))
    }

    private static func runFind(arguments: [String], projectPath: String, limit: Int?) async -> [FileSearchResult] {
        await FileSearchProcessRunner.collect(.init(
            executableURL: findURL,
            arguments: arguments,
            projectPath: projectPath,
            currentDirectoryPath: nil,
            limit: limit,
            outputPathsAreRelative: false
        ))
    }

    private static func initialArguments(projectPath: String, maxDepth: Int) -> [String] {
        var arguments = [projectPath, "-maxdepth", "\(maxDepth)"]
        appendPruneClause(into: &arguments)
        arguments.append(contentsOf: ["-type", "f", "-print"])
        return arguments
    }

    private static func fullArguments(projectPath: String) -> [String] {
        var arguments = [projectPath]
        appendPruneClause(into: &arguments)
        arguments.append(contentsOf: ["-type", "f", "-print"])
        return arguments
    }

    private static func results(from paths: [String], projectPath: String, limit: Int?) -> [FileSearchResult] {
        let selected = limit.map { Array(paths.prefix($0)) } ?? paths
        return selected.map { relativePath in
            let absolutePath = URL(fileURLWithPath: relativePath, relativeTo: URL(fileURLWithPath: projectPath)).path
            return FileSearchResult(
                id: absolutePath,
                relativePath: relativePath,
                absolutePath: absolutePath,
                fileName: URL(fileURLWithPath: absolutePath).lastPathComponent
            )
        }
    }

    private static func appendPruneClause(into arguments: inout [String]) {
        arguments.append("(")
        for (index, name) in catalog.directoryNames.enumerated() {
            if index > 0 {
                arguments.append("-o")
            }
            arguments.append(contentsOf: ["-name", name])
        }
        arguments.append(contentsOf: [")", "-prune", "-o"])
    }

    private static func appendPruneGlobs(into arguments: inout [String]) {
        for name in catalog.directoryNames {
            arguments.append(contentsOf: ["--glob", "!\(name)"])
            arguments.append(contentsOf: ["--glob", "!\(name)/**"])
        }
    }
}
