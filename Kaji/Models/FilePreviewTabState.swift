import Foundation

@MainActor
@Observable
final class FilePreviewTabState: Identifiable {
    let id = UUID()
    let projectPath: String
    private(set) var filePath: String
    private(set) var kind: FilePreviewKind

    init(projectPath: String, filePath: String, kind: FilePreviewKind) {
        self.projectPath = projectPath
        self.filePath = filePath
        self.kind = kind
    }

    var fileName: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }

    var displayTitle: String {
        fileName
    }

    var url: URL {
        URL(fileURLWithPath: filePath)
    }

    func updateFilePath(_ newPath: String) {
        guard filePath != newPath else { return }
        filePath = newPath
        kind = FilePreviewClassifier.previewKind(for: newPath) ?? .quickLook
    }
}
