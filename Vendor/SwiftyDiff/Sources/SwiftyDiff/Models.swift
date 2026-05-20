import Foundation

public struct SwiftyDiffFile: Equatable, Sendable {
    public let path: String
    public let oldPath: String?
    public let status: SwiftyDiffFileStatus
    public let hunks: [SwiftyDiffHunk]

    public init(
        path: String,
        oldPath: String?,
        status: SwiftyDiffFileStatus,
        hunks: [SwiftyDiffHunk]
    ) {
        self.path = path
        self.oldPath = oldPath
        self.status = status
        self.hunks = hunks
    }
}

public enum SwiftyDiffFileStatus: String, Sendable {
    case added = "A"
    case modified = "M"
    case deleted = "D"
    case renamed = "R"
    case copied = "C"
    case unmerged = "U"
}

public struct SwiftyDiffHunk: Equatable, Sendable {
    public let header: String
    public let oldStart: Int
    public let oldCount: Int
    public let newStart: Int
    public let newCount: Int
    public let lines: [SwiftyDiffLine]

    public init(
        header: String,
        oldStart: Int,
        oldCount: Int,
        newStart: Int,
        newCount: Int,
        lines: [SwiftyDiffLine]
    ) {
        self.header = header
        self.oldStart = oldStart
        self.oldCount = oldCount
        self.newStart = newStart
        self.newCount = newCount
        self.lines = lines
    }
}

public struct SwiftyDiffLine: Equatable, Sendable {
    public let type: SwiftyDiffLineType
    public let content: String
    public let oldLineNumber: Int?
    public let newLineNumber: Int?

    public init(
        type: SwiftyDiffLineType,
        content: String,
        oldLineNumber: Int?,
        newLineNumber: Int?
    ) {
        self.type = type
        self.content = content
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
    }
}

public enum SwiftyDiffLineType: Sendable {
    case context
    case addition
    case deletion
    case empty
}
