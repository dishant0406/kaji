import Foundation

struct DiffComment: Identifiable, Hashable {
    let id = UUID()
    let anchor: DiffCommentAnchor
    let text: String
}

struct DiffCommentDraftRequest: Identifiable, Equatable {
    let id = UUID()
    let anchor: DiffCommentAnchor
    let windowPoint: CGPoint
    let initialText: String

    init(anchor: DiffCommentAnchor, windowPoint: CGPoint, initialText: String = "") {
        self.anchor = anchor
        self.windowPoint = windowPoint
        self.initialText = initialText
    }
}

enum DiffCommentAnchor: Hashable {
    case file(path: String)
    case line(path: String, side: DiffLineSide, lineNumber: Int)

    var filePath: String {
        switch self {
        case let .file(path),
             let .line(path, _, _):
            path
        }
    }

    var summary: String {
        switch self {
        case let .file(path):
            "File \(path)"
        case let .line(path, side, lineNumber):
            "\(path):\(side.label)\(lineNumber)"
        }
    }
}

enum DiffLineSide: String, Hashable {
    case old
    case new

    var label: String {
        switch self {
        case .old: "old:"
        case .new: "new:"
        }
    }
}

enum DiffContextExpansionDirection: Hashable {
    case above
    case below
}

struct DiffHunkContextKey: Hashable {
    let filePath: String
    let hunkIndex: Int
}

struct DiffHunkContextExpansion: Hashable {
    var above = 0
    var below = 0
}
