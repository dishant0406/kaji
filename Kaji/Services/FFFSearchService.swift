import Foundation

enum FFFSearchService {
    static let maxFileResults = 30
    static let maxTextMatches = 200

    static func warm(projectPath: String) async throws {
        try Task.checkCancellation()
        try await FFFSearchIndexStore.shared.warm(projectPath: projectPath)
        try Task.checkCancellation()
    }

    static func searchFiles(query: String, in projectPath: String, limit: Int = maxFileResults) async throws -> [FileSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        try Task.checkCancellation()
        let results = try await FFFSearchIndexStore.shared.searchFiles(
            projectPath: projectPath,
            query: trimmed,
            limit: min(max(limit, 1), 1000)
        )
        try Task.checkCancellation()
        return results
    }

    static func searchText(
        query: String,
        in projectPath: String,
        limit: Int = maxTextMatches
    ) async throws -> [ProjectTextSearchFileGroup] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        try Task.checkCancellation()
        let matches = try await FFFSearchIndexStore.shared.searchText(
            projectPath: projectPath,
            query: trimmed,
            limit: min(max(limit, 1), 1000)
        )
        try Task.checkCancellation()
        return ProjectTextSearchService.group(matches)
    }

    static func removeIndexes(projectPaths: [String]) async {
        await FFFSearchIndexStore.shared.remove(projectPaths: projectPaths)
    }
}
