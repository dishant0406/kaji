import Foundation

struct WorkspaceIgnoreClassifier {
    private let catalog: WorkspaceIgnoreCatalog

    init(catalog: WorkspaceIgnoreCatalog = .bundled) {
        self.catalog = catalog
    }

    func ignoredPaths(repoPath: String, paths: [String]) -> Set<String> {
        let relativePaths = paths.compactMap { Self.relativePath(path: $0, root: repoPath) }
        guard !relativePaths.isEmpty else { return [] }
        if let ignored = GitIgnoreChecker.ignoredPathsSync(repoPath: repoPath, relativePaths: relativePaths) {
            return Set(paths.filter { path in
                guard let relative = Self.relativePath(path: path, root: repoPath) else { return false }
                return ignored.contains(relative)
            })
        }
        return Set(paths.filter { catalog.containsIgnoredComponent(in: $0) })
    }

    func shouldSkipDirectoryName(_ name: String) -> Bool {
        catalog.containsDirectoryName(name)
    }

    func pathContainsShippedIgnoredComponent(_ path: String) -> Bool {
        catalog.containsIgnoredComponent(in: path)
    }

    static func relativePath(path: String, root: String) -> String? {
        let normalizedRoot = root.hasSuffix("/") ? String(root.dropLast()) : root
        if path == normalizedRoot {
            return ""
        }
        if path.hasPrefix(normalizedRoot + "/") {
            return String(path.dropFirst(normalizedRoot.count + 1))
        }
        if path.hasPrefix("/") {
            return nil
        }
        return path
    }
}
