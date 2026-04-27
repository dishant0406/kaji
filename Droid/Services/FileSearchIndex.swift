import Foundation

actor FileSearchIndex {
    private struct CacheEntry {
        let files: [FileSearchResult]
        let loadedAt: Date

        func isFresh(cacheLifetime: TimeInterval) -> Bool {
            loadedAt.timeIntervalSinceNow >= -cacheLifetime
        }
    }

    private var cache: [String: CacheEntry] = [:]
    private var warmTasks: [String: Task<[FileSearchResult], Never>] = [:]
    private let cacheLifetime: TimeInterval = 300

    func cachedFiles(in projectPath: String) -> [FileSearchResult]? {
        cache[projectPath]?.files
    }

    func files(in projectPath: String) async -> [FileSearchResult] {
        if let entry = cache[projectPath], entry.isFresh(cacheLifetime: cacheLifetime) {
            return entry.files
        }

        if let task = warmTasks[projectPath] {
            return await task.value
        }

        return await startWarmTask(for: projectPath)
    }

    func initialFiles(in projectPath: String, maxDepth: Int, limit: Int) async -> [FileSearchResult] {
        await FileSearchScanner.scanShallow(in: projectPath, maxDepth: maxDepth, limit: limit)
    }

    func warm(projectPath: String) async {
        if let entry = cache[projectPath], entry.isFresh(cacheLifetime: cacheLifetime) {
            return
        }

        if let task = warmTasks[projectPath] {
            _ = await task.value
            return
        }

        _ = await startWarmTask(for: projectPath)
    }

    private func startWarmTask(for projectPath: String) async -> [FileSearchResult] {
        let task = Task { await FileSearchScanner.scanAll(in: projectPath) }
        warmTasks[projectPath] = task
        let files = await task.value
        cache[projectPath] = CacheEntry(files: files, loadedAt: Date())
        warmTasks[projectPath] = nil
        return files
    }
}

private enum FileSearchScanner {
    private static let prunedDirectoryNames = [
        ".git", "node_modules", ".build", "build", "DerivedData",
        "__pycache__", ".venv", "venv", "dist", ".next", ".nuxt",
        "target", "Pods", ".swiftpm", ".idea", ".vscode",
        "vendor", "coverage", ".cache", ".parcel-cache",
    ]

    private static let rgURL = URL(fileURLWithPath: "/opt/homebrew/bin/rg")
    private static let findURL = URL(fileURLWithPath: "/usr/bin/find")

    static func scanAll(in projectPath: String) async -> [FileSearchResult] {
        if FileManager.default.isExecutableFile(atPath: rgURL.path) {
            return await runRipgrep(in: projectPath, glob: nil, limit: nil)
        }
        return await runFind(
            arguments: fullArguments(projectPath: projectPath),
            projectPath: projectPath,
            limit: nil
        )
    }

    static func scanShallow(in projectPath: String, maxDepth: Int, limit: Int) async -> [FileSearchResult] {
        await runFind(
            arguments: initialArguments(projectPath: projectPath, maxDepth: maxDepth),
            projectPath: projectPath,
            limit: limit
        )
    }

    private static func runRipgrep(in projectPath: String, glob: String?, limit: Int?) async -> [FileSearchResult] {
        var arguments = ["--files", "--hidden", "--no-ignore"]
        appendPruneGlobs(into: &arguments)
        if let glob {
            arguments.append(contentsOf: ["--glob", glob])
        }
        return await FileSearchProcessRunner.collect(
            executableURL: rgURL,
            arguments: arguments,
            projectPath: projectPath,
            currentDirectoryPath: projectPath,
            limit: limit,
            outputPathsAreRelative: true
        )
    }

    private static func runFind(arguments: [String], projectPath: String, limit: Int?) async -> [FileSearchResult] {
        await FileSearchProcessRunner.collect(
            executableURL: findURL,
            arguments: arguments,
            projectPath: projectPath,
            currentDirectoryPath: nil,
            limit: limit,
            outputPathsAreRelative: false
        )
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

    private static func appendPruneClause(into arguments: inout [String]) {
        arguments.append("(")
        for (index, name) in prunedDirectoryNames.enumerated() {
            if index > 0 {
                arguments.append("-o")
            }
            arguments.append(contentsOf: ["-name", name])
        }
        arguments.append(contentsOf: [")", "-prune", "-o"])
    }

    private static func appendPruneGlobs(into arguments: inout [String]) {
        for name in prunedDirectoryNames {
            arguments.append(contentsOf: ["--glob", "!\(name)"])
            arguments.append(contentsOf: ["--glob", "!\(name)/**"])
        }
    }
}
