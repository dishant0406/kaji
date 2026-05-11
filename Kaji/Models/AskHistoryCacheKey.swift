import Foundation

struct AskHistoryCacheKey: Equatable {
    let provider: AskProvider
    let projectPath: String?
    let query: String
}
