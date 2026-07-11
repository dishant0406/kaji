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

enum ProjectTextSearchDisplayRow: Identifiable, Equatable {
    case file(ProjectTextSearchFileGroup)
    case match(ProjectTextSearchMatch)

    var id: String {
        switch self {
        case let .file(group):
            "file:\(group.id)"
        case let .match(match):
            "match:\(match.id)"
        }
    }

    static func rows(from groups: [ProjectTextSearchFileGroup]) -> [ProjectTextSearchDisplayRow] {
        groups.reduce(into: []) { rows, group in
            rows.append(.file(group))
            rows.append(contentsOf: group.matches.map(ProjectTextSearchDisplayRow.match))
        }
    }
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
