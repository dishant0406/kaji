import Foundation

enum GitCommitFlowStage: Hashable {
    case loadingFiles
    case selectFiles
    case chooseMessageMode
    case reviewMessage
    case committing
    case result
}

enum GitCommitMessageMode: String, Hashable {
    case manual
    case generate

    var title: String {
        switch self {
        case .manual:
            "Write manually"
        case .generate:
            "Generate commit message"
        }
    }
}

struct GitCommitFlowState: Hashable {
    var stage = GitCommitFlowStage.loadingFiles
    var files: [GitStatusFile] = []
    var selectedPaths: Set<String> = []
    var message = ""
    var nativeDraft = ""
    var statusText: String?
    var errorText: String?
    var isGenerating = false
    var generationText: String?
    var generatedMessage: String?
    var committedHash: String?

    var selectedFiles: [GitStatusFile] {
        files.filter { selectedPaths.contains($0.path) }
    }

    var hasSelection: Bool {
        !selectedPaths.isEmpty
    }

    var showsSearchField: Bool {
        stage == .loadingFiles || stage == .selectFiles || stage == .chooseMessageMode
    }
}
