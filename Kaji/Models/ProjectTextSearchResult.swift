import Foundation

struct ProjectTextSearchMatch: Identifiable, Equatable {
    let id: String
    let filePath: String
    let relativePath: String
    let line: Int
    let column: Int
    let preview: String
}

struct ProjectTextSearchFileGroup: Identifiable, Equatable {
    let id: String
    let filePath: String
    let relativePath: String
    let matches: [ProjectTextSearchMatch]
}

struct ProjectTextReplacePreview: Equatable {
    let fileCount: Int
    let matchCount: Int
    let replacement: String

    static func make(groups: [ProjectTextSearchFileGroup], replacement: String) -> ProjectTextReplacePreview {
        ProjectTextReplacePreview(
            fileCount: groups.count,
            matchCount: groups.reduce(0) { $0 + $1.matches.count },
            replacement: replacement
        )
    }
}
