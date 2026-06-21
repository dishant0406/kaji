import Foundation

struct GitCommitMessageAgentResult: Hashable {
    let message: String
    let modelLabel: String?

    init(message: String, modelLabel: String? = nil) {
        self.message = message
        self.modelLabel = modelLabel
    }
}
