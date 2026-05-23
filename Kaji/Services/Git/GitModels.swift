import Foundation

struct NumstatEntry {
    let additions: Int?
    let deletions: Int?
    let isBinary: Bool
}

struct GitStatusFile: Identifiable, Hashable {
    let path: String
    let oldPath: String?
    let xStatus: Character
    let yStatus: Character
    let additions: Int?
    let deletions: Int?
    let isBinary: Bool

    var id: String { path }

    var stageIdentity: String {
        "\(path):\(xStatus):\(yStatus):\(additions ?? -1):\(deletions ?? -1):\(isBinary)"
    }

    var isStaged: Bool {
        let staged: Set<Character> = ["A", "M", "D", "R", "C"]
        return staged.contains(xStatus)
    }

    var isUnstaged: Bool {
        let unstaged: Set<Character> = ["M", "D", "?"]
        return unstaged.contains(yStatus) || (xStatus == "?" && yStatus == "?")
    }

    var statusText: String {
        switch (xStatus, yStatus) {
        case ("A", _),
             (_, "A"):
            "A"
        case ("D", _),
             (_, "D"):
            "D"
        case ("R", _),
             (_, "R"):
            "R"
        case ("C", _),
             (_, "C"):
            "C"
        case ("M", _),
             (_, "M"):
            "M"
        case ("U", _),
             (_, "U"):
            "U"
        default:
            "?"
        }
    }

    var paletteStatusText: String {
        if xStatus == "?", yStatus == "?" {
            return "U"
        }
        return statusText
    }

    var statSummaryText: String {
        if isBinary { return "Binary" }
        let additionsText = additions.map { "+\($0)" }
        let deletionsText = deletions.map { "-\($0)" }
        return [additionsText, deletionsText].compactMap(\.self).joined(separator: " ")
    }

    var paletteAnnotationText: String {
        [paletteStatusText, statSummaryText].filter { !$0.isEmpty }.joined(separator: " ")
    }

    var stagedStatusText: String {
        String(xStatus)
    }

    var unstagedStatusText: String {
        if xStatus == "?", yStatus == "?" {
            return "U"
        }
        return String(yStatus)
    }
}

struct GitCommit: Hashable, Identifiable {
    let hash: String
    let shortHash: String
    let subject: String
    let authorName: String
    let authorDate: Date
    let refs: [GitRef]
    let parentHashes: [String]

    var id: String { hash }
    var isMerge: Bool { parentHashes.count > 1 }
}

struct GitRef: Hashable {
    enum Kind: Hashable {
        case localBranch
        case remoteBranch
        case tag
        case head
    }

    let name: String
    let kind: Kind
}

struct DiffDisplayRow: Identifiable {
    enum Kind {
        case hunk
        case context
        case addition
        case deletion
        case collapsed
    }

    let id = UUID()
    let kind: Kind
    let oldLineNumber: Int?
    let newLineNumber: Int?
    let oldText: String?
    let newText: String?
    let text: String
}
