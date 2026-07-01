import Foundation

struct AgentChangedFilesSnapshotPolicy {
    static let `default` = AgentChangedFilesSnapshotPolicy()

    let ignoreClassifier: WorkspaceIgnoreClassifier?
    let maxStoredFiles: Int

    init(
        ignoreClassifier: WorkspaceIgnoreClassifier? = WorkspaceIgnoreClassifier(),
        maxStoredFiles: Int = 500
    ) {
        self.ignoreClassifier = ignoreClassifier
        self.maxStoredFiles = max(1, maxStoredFiles)
    }

    func capturedFiles(from files: [AgentChangedFile]) -> [AgentChangedFile] {
        Array(files.lazy.filter(shouldCapture).prefix(maxStoredFiles))
    }

    private func shouldCapture(_ file: AgentChangedFile) -> Bool {
        guard let ignoreClassifier else { return true }
        return !ignoreClassifier.pathContainsShippedIgnoredComponent(file.path) &&
            !(file.oldPath.map(ignoreClassifier.pathContainsShippedIgnoredComponent) ?? false)
    }
}
