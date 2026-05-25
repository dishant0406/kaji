import Foundation

enum FFFSearchService {
    static let maxFileResults = 30
    static let maxTextMatches = 200

    static func warm(projectPath: String) async throws {
        let index = try await FFFSearchIndexStore.shared.index(for: projectPath)
        try index.waitForScan()
    }

    static func searchFiles(query: String, in projectPath: String, limit: Int = maxFileResults) async throws -> [FileSearchResult] {
        let index = try await FFFSearchIndexStore.shared.index(for: projectPath)
        return try index.searchFiles(query: query.trimmingCharacters(in: .whitespacesAndNewlines), limit: limit)
    }

    static func searchText(
        query: String,
        in projectPath: String,
        limit: Int = maxTextMatches
    ) async throws -> [ProjectTextSearchFileGroup] {
        let index = try await FFFSearchIndexStore.shared.index(for: projectPath)
        return try ProjectTextSearchService.group(index.searchText(
            query: query.trimmingCharacters(in: .whitespacesAndNewlines),
            limit: limit
        ))
    }
}
