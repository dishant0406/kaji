import Foundation
import SwiftyDiff

struct ParsedDiffRows {
    let rows: [DiffDisplayRow]
    let additions: Int
    let deletions: Int
}

enum SwiftyDiffAdapter {
    static func parseRows(_ patch: String) -> ParsedDiffRows {
        let files = SwiftyDiffParser.parse(patch)
        let rows = files.flatMap(rows)
        return ParsedDiffRows(
            rows: rows,
            additions: rows.count(where: { $0.kind == .addition }),
            deletions: rows.count(where: { $0.kind == .deletion })
        )
    }

    static func collapseContextRows(_ rows: [DiffDisplayRow]) -> [DiffDisplayRow] {
        var output: [DiffDisplayRow] = []
        var index = 0
        let leadingContext = 3
        let trailingContext = 3
        let collapseThreshold = 12

        while index < rows.count {
            let row = rows[index]
            if row.kind != .context {
                output.append(row)
                index += 1
                continue
            }

            var end = index
            while end < rows.count, rows[end].kind == .context {
                end += 1
            }

            let runLength = end - index
            if runLength <= collapseThreshold {
                output.append(contentsOf: rows[index ..< end])
            } else {
                let startKeepEnd = index + leadingContext
                let endKeepStart = end - trailingContext
                output.append(contentsOf: rows[index ..< startKeepEnd])
                output.append(DiffDisplayRow(
                    kind: .collapsed,
                    oldLineNumber: nil,
                    newLineNumber: nil,
                    oldText: nil,
                    newText: nil,
                    text: "\(runLength - leadingContext - trailingContext) unmodified lines"
                ))
                output.append(contentsOf: rows[endKeepStart ..< end])
            }

            index = end
        }

        return output
    }

    private static func rows(from file: SwiftyDiffFile) -> [DiffDisplayRow] {
        file.hunks.flatMap { hunk in
            [hunkRow(from: hunk)] + hunk.lines.map(row)
        }
    }

    private static func hunkRow(from hunk: SwiftyDiffHunk) -> DiffDisplayRow {
        DiffDisplayRow(
            kind: .hunk,
            oldLineNumber: nil,
            newLineNumber: nil,
            oldText: nil,
            newText: nil,
            text: hunk.header
        )
    }

    private static func row(from line: SwiftyDiffLine) -> DiffDisplayRow {
        let kind = rowKind(for: line.type)
        return DiffDisplayRow(
            kind: kind,
            oldLineNumber: line.oldLineNumber,
            newLineNumber: line.newLineNumber,
            oldText: oldText(for: line),
            newText: newText(for: line),
            text: text(for: line)
        )
    }

    private static func rowKind(for type: SwiftyDiffLineType) -> DiffDisplayRow.Kind {
        switch type {
        case .context,
             .empty:
            .context
        case .addition:
            .addition
        case .deletion:
            .deletion
        }
    }

    private static func oldText(for line: SwiftyDiffLine) -> String? {
        switch line.type {
        case .context,
             .empty,
             .deletion:
            line.content
        case .addition:
            nil
        }
    }

    private static func newText(for line: SwiftyDiffLine) -> String? {
        switch line.type {
        case .context,
             .empty,
             .addition:
            line.content
        case .deletion:
            nil
        }
    }

    private static func text(for line: SwiftyDiffLine) -> String {
        switch line.type {
        case .context,
             .empty:
            " \(line.content)"
        case .addition:
            "+\(line.content)"
        case .deletion:
            "-\(line.content)"
        }
    }
}
