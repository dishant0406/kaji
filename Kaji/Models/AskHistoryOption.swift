import Foundation

struct AskHistoryOption: Hashable, Identifiable {
    let provider: AskProvider
    let sessionID: String
    let title: String
    let detail: String
    let projectPath: String?
    let updatedAt: Date

    var id: String {
        "\(provider.rawValue):\(sessionID)"
    }
}
