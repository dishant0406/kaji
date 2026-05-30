import Foundation

struct AgentChangedFilesSnapshotPolicy {
    static let `default` = AgentChangedFilesSnapshotPolicy()

    let ignoredPathComponents: Set<String>
    let maxStoredFiles: Int

    init(
        ignoredPathComponents: Set<String> = [
            ".git",
            ".build",
            ".next",
            ".swiftpm",
            "DerivedData",
            "build",
            "coverage",
            "dist",
            "node_modules",
        ],
        maxStoredFiles: Int = 500
    ) {
        self.ignoredPathComponents = ignoredPathComponents
        self.maxStoredFiles = maxStoredFiles
    }

    func capturedFiles(from files: [AgentChangedFile]) -> [AgentChangedFile] {
        Array(files.lazy.filter(shouldCapture).prefix(maxStoredFiles))
    }

    private func shouldCapture(_ file: AgentChangedFile) -> Bool {
        !pathContainsIgnoredComponent(file.path) &&
            !(file.oldPath.map(pathContainsIgnoredComponent) ?? false)
    }

    private func pathContainsIgnoredComponent(_ path: String) -> Bool {
        path.split(separator: "/").contains { ignoredPathComponents.contains(String($0)) }
    }
}
