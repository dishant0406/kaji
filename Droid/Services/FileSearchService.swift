import Foundation

struct FileSearchResult: Identifiable, Equatable, Sendable {
    let id: String
    let relativePath: String
    let absolutePath: String
    let fileName: String
}

enum FileSearchService {
    static let maxResults = 30
    private static let initialMaxDepth = 4
    private static let initialCandidateLimit = 150
    private static let index = FileSearchIndex()

    static func warm(projectPath: String) async {
        await index.warm(projectPath: projectPath)
    }

    static func search(query: String, in projectPath: String) async -> [FileSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if let cached = await index.cachedFiles(in: projectPath) {
            if trimmed.isEmpty {
                return FileSearchRanker.rankInitialCandidates(cached, maxResults: maxResults)
            }
            return FileSearchRanker.rankCandidates(cached, query: trimmed, maxResults: maxResults)
        }

        Task { await index.warm(projectPath: projectPath) }

        if trimmed.isEmpty {
            let candidates = await index.initialFiles(
                in: projectPath,
                maxDepth: initialMaxDepth,
                limit: initialCandidateLimit
            )
            return FileSearchRanker.rankInitialCandidates(candidates, maxResults: maxResults)
        }

        let candidates = await index.files(in: projectPath)
        return FileSearchRanker.rankCandidates(candidates, query: trimmed, maxResults: maxResults)
    }
}
