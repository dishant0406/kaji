import Foundation

enum FFFSearchService {
    static let maxFileResults = 30
    static let maxTextMatches = 200

    private static let queue = DispatchQueue(label: "app.kaji.fff-search", qos: .userInitiated)

    static func warm(projectPath: String) async throws {
        let index = try await FFFSearchIndexStore.shared.index(for: projectPath)
        try await offMain {
            try index.waitForScan()
        }
    }

    static func searchFiles(query: String, in projectPath: String, limit: Int = maxFileResults) async throws -> [FileSearchResult] {
        let index = try await FFFSearchIndexStore.shared.index(for: projectPath)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        try Task.checkCancellation()
        return try await offMain {
            try Task.checkCancellation()
            return try index.searchFiles(query: trimmed, limit: limit)
        }
    }

    static func searchText(
        query: String,
        in projectPath: String,
        limit: Int = maxTextMatches
    ) async throws -> [ProjectTextSearchFileGroup] {
        let index = try await FFFSearchIndexStore.shared.index(for: projectPath)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        try Task.checkCancellation()
        return try await offMain {
            try Task.checkCancellation()
            return try ProjectTextSearchService.group(index.searchText(query: trimmed, limit: limit))
        }
    }

    private static func offMain<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    try continuation.resume(returning: work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
