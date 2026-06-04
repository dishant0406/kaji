import Foundation

struct DiffRenderPlan {
    let unifiedChunks: [UnifiedDiffRenderChunk]
    let splitChunks: [SplitDiffRenderChunk]
    let maxLineNumber: Int
    let maxDisplayColumns: Int
    let oldLineRowIndexes: [Int: [Int]]
    let newLineRowIndexes: [Int: [Int]]
    let changedRowIndexes: [Int]

    init(rows: [DiffDisplayRow]) {
        unifiedChunks = Self.buildUnifiedChunks(from: rows)
        splitChunks = Self.buildSplitChunks(from: rows)
        maxLineNumber = Self.maxLineNumber(in: rows)
        maxDisplayColumns = Self.maxDisplayColumns(in: rows)
        oldLineRowIndexes = Self.lineRowIndexes(rows: rows, keyPath: \.oldLineNumber)
        newLineRowIndexes = Self.lineRowIndexes(rows: rows, keyPath: \.newLineNumber)
        changedRowIndexes = Self.changedRowIndexes(in: rows)
    }

    private static func buildUnifiedChunks(from rows: [DiffDisplayRow]) -> [UnifiedDiffRenderChunk] {
        var chunks: [UnifiedDiffRenderChunk] = []
        var currentRows: [DiffDisplayRow] = []
        var currentHunkIndex: Int?
        var nextHunkIndex = 0

        for row in rows {
            if row.kind == .hunk {
                if !currentRows.isEmpty {
                    chunks.append(.codeBlock(DiffRenderCodeBlock(rows: currentRows, hunkIndex: currentHunkIndex, side: .both)))
                    currentRows = []
                }
                currentHunkIndex = nextHunkIndex
                nextHunkIndex += 1
                currentRows.append(row)
            } else if row.kind == .collapsed {
                if !currentRows.isEmpty {
                    chunks.append(.codeBlock(DiffRenderCodeBlock(rows: currentRows, hunkIndex: currentHunkIndex, side: .both)))
                    currentRows = []
                }
                chunks.append(.divider(text: row.text, hunkIndex: currentHunkIndex))
            } else {
                currentRows.append(row)
            }
        }

        if !currentRows.isEmpty {
            chunks.append(.codeBlock(DiffRenderCodeBlock(rows: currentRows, hunkIndex: currentHunkIndex, side: .both)))
        }

        return chunks
    }

    private static func buildSplitChunks(from rows: [DiffDisplayRow]) -> [SplitDiffRenderChunk] {
        let paired = SplitDiffRenderPairedRow.pair(rows)
        var chunks: [SplitDiffRenderChunk] = []
        var leftRows: [DiffDisplayRow] = []
        var rightRows: [DiffDisplayRow] = []
        var currentHunkIndex: Int?

        for paired in paired {
            if paired.kind == .hunk {
                appendSplitCodeBlock(leftRows: &leftRows, rightRows: &rightRows, hunkIndex: currentHunkIndex, chunks: &chunks)
                currentHunkIndex = paired.hunkIndex
                leftRows.append(paired.left ?? emptyRow(kind: .context))
                rightRows.append(paired.right ?? emptyRow(kind: .context))
            } else if paired.kind == .collapsed {
                appendSplitCodeBlock(leftRows: &leftRows, rightRows: &rightRows, hunkIndex: currentHunkIndex, chunks: &chunks)
                let text = paired.left?.text ?? paired.right?.text ?? ""
                chunks.append(.divider(text: text, hunkIndex: currentHunkIndex))
            } else {
                leftRows.append(paired.left ?? emptyRow(kind: .context))
                rightRows.append(paired.right ?? emptyRow(kind: .context))
            }
        }

        appendSplitCodeBlock(leftRows: &leftRows, rightRows: &rightRows, hunkIndex: currentHunkIndex, chunks: &chunks)
        return chunks
    }

    private static func appendSplitCodeBlock(
        leftRows: inout [DiffDisplayRow],
        rightRows: inout [DiffDisplayRow],
        hunkIndex: Int?,
        chunks: inout [SplitDiffRenderChunk]
    ) {
        guard !leftRows.isEmpty || !rightRows.isEmpty else { return }
        padToEqualLength(&leftRows, &rightRows)
        chunks.append(.codeBlock(SplitDiffRenderCodeBlock(leftRows: leftRows, rightRows: rightRows, hunkIndex: hunkIndex)))
        leftRows = []
        rightRows = []
    }

    private static func padToEqualLength(_ left: inout [DiffDisplayRow], _ right: inout [DiffDisplayRow]) {
        while left.count < right.count {
            left.append(emptyRow(kind: .context))
        }
        while right.count < left.count {
            right.append(emptyRow(kind: .context))
        }
    }

    private static func emptyRow(kind: DiffDisplayRow.Kind) -> DiffDisplayRow {
        DiffDisplayRow(kind: kind, oldLineNumber: nil, newLineNumber: nil, oldText: nil, newText: nil, text: "")
    }

    private static func maxLineNumber(in rows: [DiffDisplayRow]) -> Int {
        rows.reduce(0) { partialResult, row in
            max(partialResult, row.oldLineNumber ?? 0, row.newLineNumber ?? 0)
        }
    }

    private static func maxDisplayColumns(in rows: [DiffDisplayRow]) -> Int {
        rows.reduce(0) { partialResult, row in
            let text = switch row.kind {
            case .deletion: row.oldText ?? ""
            case .addition: row.newText ?? ""
            default: row.newText ?? row.oldText ?? row.text
            }
            return max(partialResult, text.utf16.count)
        }
    }

    private static func lineRowIndexes(rows: [DiffDisplayRow], keyPath: KeyPath<DiffDisplayRow, Int?>) -> [Int: [Int]] {
        var indexes: [Int: [Int]] = [:]
        for (index, row) in rows.enumerated() {
            guard let lineNumber = row[keyPath: keyPath] else { continue }
            indexes[lineNumber, default: []].append(index)
        }
        return indexes
    }

    private static func changedRowIndexes(in rows: [DiffDisplayRow]) -> [Int] {
        rows.indices.filter { rows[$0].kind == .addition || rows[$0].kind == .deletion }
    }
}

struct DiffRenderCodeBlock {
    let rows: [DiffDisplayRow]
    let hunkIndex: Int?
    let maxDisplayColumns: Int
    let signature: Int

    init(rows: [DiffDisplayRow], hunkIndex: Int?, side: DiffBackgroundSide) {
        self.rows = rows
        self.hunkIndex = hunkIndex
        maxDisplayColumns = DiffRenderPlan.maxDisplayColumnsForBlock(rows)
        signature = DiffRenderPlan.contentSignature(rows: rows, side: side)
    }
}

enum UnifiedDiffRenderChunk {
    case divider(text: String, hunkIndex: Int?)
    case codeBlock(DiffRenderCodeBlock)
}

struct SplitDiffRenderCodeBlock {
    let leftRows: [DiffDisplayRow]
    let rightRows: [DiffDisplayRow]
    let hunkIndex: Int?
    let leftMaxDisplayColumns: Int
    let rightMaxDisplayColumns: Int
    let leftSignature: Int
    let rightSignature: Int

    init(leftRows: [DiffDisplayRow], rightRows: [DiffDisplayRow], hunkIndex: Int?) {
        self.leftRows = leftRows
        self.rightRows = rightRows
        self.hunkIndex = hunkIndex
        leftMaxDisplayColumns = DiffRenderPlan.maxDisplayColumnsForBlock(leftRows)
        rightMaxDisplayColumns = DiffRenderPlan.maxDisplayColumnsForBlock(rightRows)
        leftSignature = DiffRenderPlan.contentSignature(rows: leftRows, side: .left)
        rightSignature = DiffRenderPlan.contentSignature(rows: rightRows, side: .right)
    }
}

enum SplitDiffRenderChunk {
    case divider(text: String, hunkIndex: Int?)
    case codeBlock(SplitDiffRenderCodeBlock)
}

private struct SplitDiffRenderPairedRow {
    enum Kind {
        case content
        case hunk
        case collapsed
    }

    let kind: Kind
    let hunkIndex: Int?
    let left: DiffDisplayRow?
    let right: DiffDisplayRow?

    static func pair(_ rows: [DiffDisplayRow]) -> [SplitDiffRenderPairedRow] {
        var result: [SplitDiffRenderPairedRow] = []
        var index = 0
        var hunkIndex = 0

        while index < rows.count {
            let row = rows[index]
            switch row.kind {
            case .hunk:
                result.append(SplitDiffRenderPairedRow(kind: .hunk, hunkIndex: hunkIndex, left: row, right: nil))
                hunkIndex += 1
                index += 1
            case .collapsed:
                result.append(SplitDiffRenderPairedRow(kind: .collapsed, hunkIndex: hunkIndex - 1, left: row, right: nil))
                index += 1
            case .context:
                result.append(SplitDiffRenderPairedRow(kind: .content, hunkIndex: hunkIndex - 1, left: row, right: row))
                index += 1
            case .deletion:
                var deletions: [DiffDisplayRow] = []
                while index < rows.count, rows[index].kind == .deletion {
                    deletions.append(rows[index])
                    index += 1
                }
                var additions: [DiffDisplayRow] = []
                while index < rows.count, rows[index].kind == .addition {
                    additions.append(rows[index])
                    index += 1
                }
                let maxCount = max(deletions.count, additions.count)
                for pairIndex in 0 ..< maxCount {
                    result.append(SplitDiffRenderPairedRow(
                        kind: .content,
                        hunkIndex: hunkIndex - 1,
                        left: pairIndex < deletions.count ? deletions[pairIndex] : nil,
                        right: pairIndex < additions.count ? additions[pairIndex] : nil
                    ))
                }
            case .addition:
                result.append(SplitDiffRenderPairedRow(kind: .content, hunkIndex: hunkIndex - 1, left: nil, right: row))
                index += 1
            }
        }

        return result
    }
}

extension DiffRenderPlan {
    static func maxDisplayColumnsForBlock(_ rows: [DiffDisplayRow]) -> Int {
        maxDisplayColumns(in: rows)
    }

    static func contentSignature(rows: [DiffDisplayRow], side: DiffBackgroundSide) -> Int {
        var hasher = Hasher()
        hasher.combine(backgroundSideHash(side))
        hasher.combine(rows.count)
        for row in rows {
            hasher.combine(diffRowKindHash(row.kind))
            hasher.combine(row.oldLineNumber)
            hasher.combine(row.newLineNumber)
            hasher.combine(row.oldText)
            hasher.combine(row.newText)
            hasher.combine(row.text)
            if let segments = row.oldInlineSegments {
                for segment in segments {
                    hasher.combine(segment.text)
                    hasher.combine(segment.emphasized)
                }
            }
            if let segments = row.newInlineSegments {
                for segment in segments {
                    hasher.combine(segment.text)
                    hasher.combine(segment.emphasized)
                }
            }
        }
        return hasher.finalize()
    }

    private static func diffRowKindHash(_ kind: DiffDisplayRow.Kind) -> Int {
        switch kind {
        case .hunk: 1
        case .context: 2
        case .addition: 3
        case .deletion: 4
        case .collapsed: 5
        }
    }

    private static func backgroundSideHash(_ side: DiffBackgroundSide) -> Int {
        switch side {
        case .left: 1
        case .right: 2
        case .both: 3
        }
    }
}
