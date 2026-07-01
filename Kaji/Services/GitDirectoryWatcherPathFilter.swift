import Foundation

struct GitDirectoryWatcherPathFilter {
    private let repoPath: String
    private let classifier: WorkspaceIgnoreClassifier

    init(repoPath: String, classifier: WorkspaceIgnoreClassifier = WorkspaceIgnoreClassifier()) {
        self.repoPath = repoPath
        self.classifier = classifier
    }

    func relevantPaths(from paths: [String]) -> [String] {
        let ignored = classifier.ignoredPaths(repoPath: repoPath, paths: paths)
        return paths.filter { !ignored.contains($0) }
    }

    static func shouldIgnore(path: String) -> Bool {
        WorkspaceIgnoreClassifier().pathContainsShippedIgnoredComponent(path)
    }
}
