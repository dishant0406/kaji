import Foundation

struct FileSearchResult: Identifiable, Equatable {
    let id: String
    let relativePath: String
    let absolutePath: String
    let fileName: String
}

enum FileSearchService {
    static let maxResults = 30

    static func warm(projectPath: String) async {
        try? await FFFSearchService.warm(projectPath: projectPath)
    }

    static func search(query: String, in projectPath: String) async -> [FileSearchResult] {
        await (try? FFFSearchService.searchFiles(query: query, in: projectPath, limit: maxResults)) ?? []
    }
}
