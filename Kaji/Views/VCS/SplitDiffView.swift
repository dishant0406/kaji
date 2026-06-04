import SwiftUI

struct SplitDiffView: View {
    let rows: [DiffDisplayRow]
    let renderPlan: DiffRenderPlan
    let filePath: String
    var onViewMore: ((Int, DiffContextExpansionDirection) -> Void)?
    var contextExpansion: ((Int) -> DiffHunkContextExpansion)?
    var fileLineCount: Int?
    var onCommentRequest: ((DiffCommentAnchor, CGPoint) -> Void)?
    var comments: [DiffComment] = []
    var suppressLeadingTopBorder: Bool = false

    private var chunks: [SplitDiffRenderChunk] {
        renderPlan.splitChunks
    }

    private var numberColumnWidth: CGFloat {
        lineNumberWidth(for: renderPlan.maxLineNumber)
    }

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(chunks.enumerated()), id: \.offset) { index, chunk in
                switch chunk {
                case let .divider(text, hunkIndex):
                    DiffSectionDivider(
                        text: text,
                        hunkIndex: hunkIndex,
                        onViewMore: onViewMore,
                        showsTopBorder: !(index == 0 && suppressLeadingTopBorder)
                    )
                case let .codeBlock(block):
                    splitCodeBlock(block)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Split diff, \(filePath)")
    }

    private func splitCodeBlock(_ block: SplitDiffRenderCodeBlock) -> some View {
        let lineCount = max(block.leftRows.count, block.rightRows.count)
        let height = CGFloat(lineCount) * diffLineHeight
        let leftMeta = buildDiffMetadata(from: block.leftRows)
        let rightMeta = buildDiffMetadata(from: block.rightRows)

        return ZStack(alignment: .leading) {
            HStack(alignment: .top, spacing: 0) {
                DiffGutterBridge(
                    metadata: leftMeta,
                    filePath: filePath,
                    mode: .singleOld,
                    columnWidth: numberColumnWidth,
                    onCommentRequest: onCommentRequest,
                    comments: comments
                )
                .frame(width: numberColumnWidth + 1 + DiffGutterNSView.commentBubbleMaxWidth, height: height, alignment: .leading)
                .frame(width: numberColumnWidth + 1, height: height, alignment: .leading)
                .zIndex(2)

                ScrollView(.horizontal, showsIndicators: false) {
                    DiffContentBridge(
                        rows: block.leftRows,
                        backgroundSide: .left,
                        signature: block.leftSignature,
                        maxDisplayColumns: block.leftMaxDisplayColumns
                    )
                    .frame(height: height)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .zIndex(0)

                Rectangle().fill(KajiTheme.border).frame(width: 1)
                    .zIndex(1)

                DiffGutterBridge(
                    metadata: rightMeta,
                    filePath: filePath,
                    mode: .singleNew,
                    columnWidth: numberColumnWidth,
                    onCommentRequest: onCommentRequest,
                    comments: comments
                )
                .frame(width: numberColumnWidth + 1 + DiffGutterNSView.commentBubbleMaxWidth, height: height, alignment: .leading)
                .frame(width: numberColumnWidth + 1, height: height, alignment: .leading)
                .zIndex(2)

                ScrollView(.horizontal, showsIndicators: false) {
                    DiffContentBridge(
                        rows: block.rightRows,
                        backgroundSide: .right,
                        signature: block.rightSignature,
                        maxDisplayColumns: block.rightMaxDisplayColumns
                    )
                    .frame(height: height)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .zIndex(0)
            }

            hunkControls(hunkIndex: block.hunkIndex)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }

    @ViewBuilder
    private func hunkControls(hunkIndex: Int?) -> some View {
        if let hunkIndex, let onViewMore {
            VStack {
                if canExpandAbove(hunkIndex: hunkIndex) {
                    HunkContextButton(direction: .above, count: contextExpansion?(hunkIndex).above ?? 0) {
                        onViewMore(hunkIndex, .above)
                    }
                }
                Spacer(minLength: 0)
                if canExpandBelow(hunkIndex: hunkIndex) {
                    HunkContextButton(direction: .below, count: contextExpansion?(hunkIndex).below ?? 0) {
                        onViewMore(hunkIndex, .below)
                    }
                }
            }
            .padding(.leading, 4)
            .padding(.vertical, 2)
            .frame(width: numberColumnWidth + 121, alignment: .leading)
            .zIndex(3)
        }
    }

    private func canExpandAbove(hunkIndex: Int) -> Bool {
        guard let blockRows = rowsForHunk(hunkIndex), let firstLine = blockRows.compactMap(\.newLineNumber).min() else { return false }
        return firstLine > 1
    }

    private func canExpandBelow(hunkIndex: Int) -> Bool {
        guard let fileLineCount,
              let blockRows = rowsForHunk(hunkIndex),
              let lastLine = blockRows.compactMap(\.newLineNumber).max()
        else { return true }
        return lastLine < fileLineCount
    }

    private func rowsForHunk(_ hunkIndex: Int) -> [DiffDisplayRow]? {
        var currentIndex = -1
        var rowsForHunk: [DiffDisplayRow] = []
        for row in rows {
            if row.kind == .hunk { currentIndex += 1 }
            if currentIndex == hunkIndex { rowsForHunk.append(row) }
            if currentIndex > hunkIndex { break }
        }
        return rowsForHunk.isEmpty ? nil : rowsForHunk
    }
}

enum SplitDiffChunk {
    case divider(text: String, hunkIndex: Int?)
    case codeBlock(leftRows: [DiffDisplayRow], rightRows: [DiffDisplayRow], hunkIndex: Int?)
}

func buildSplitDiffChunks(from rows: [DiffDisplayRow]) -> [SplitDiffChunk] {
    let paired = SplitDiffPairedRow.pair(rows)
    var chunks: [SplitDiffChunk] = []
    var leftRows: [DiffDisplayRow] = []
    var rightRows: [DiffDisplayRow] = []
    var currentHunkIndex: Int?

    for paired in paired {
        if paired.kind == .hunk {
            if !leftRows.isEmpty || !rightRows.isEmpty {
                padToEqualLength(&leftRows, &rightRows)
                chunks.append(.codeBlock(leftRows: leftRows, rightRows: rightRows, hunkIndex: currentHunkIndex))
                leftRows = []
                rightRows = []
            }
            currentHunkIndex = paired.hunkIndex
            leftRows.append(paired.left ?? emptyRow(kind: .context))
            rightRows.append(paired.right ?? emptyRow(kind: .context))
        } else if paired.kind == .collapsed {
            if !leftRows.isEmpty || !rightRows.isEmpty {
                padToEqualLength(&leftRows, &rightRows)
                chunks.append(.codeBlock(leftRows: leftRows, rightRows: rightRows, hunkIndex: currentHunkIndex))
                leftRows = []
                rightRows = []
            }
            let rawText = paired.left?.text ?? paired.right?.text ?? ""
            chunks.append(.divider(text: rawText, hunkIndex: currentHunkIndex))
        } else {
            leftRows.append(paired.left ?? emptyRow(kind: .context))
            rightRows.append(paired.right ?? emptyRow(kind: .context))
        }
    }

    if !leftRows.isEmpty || !rightRows.isEmpty {
        padToEqualLength(&leftRows, &rightRows)
        chunks.append(.codeBlock(leftRows: leftRows, rightRows: rightRows, hunkIndex: currentHunkIndex))
    }

    return chunks
}

private func padToEqualLength(_ left: inout [DiffDisplayRow], _ right: inout [DiffDisplayRow]) {
    while left.count < right.count {
        left.append(emptyRow(kind: .context))
    }
    while right.count < left.count {
        right.append(emptyRow(kind: .context))
    }
}

private func emptyRow(kind: DiffDisplayRow.Kind) -> DiffDisplayRow {
    DiffDisplayRow(
        kind: kind,
        oldLineNumber: nil,
        newLineNumber: nil,
        oldText: nil,
        newText: nil,
        text: ""
    )
}

struct SplitDiffPairedRow: Identifiable {
    enum Kind {
        case content
        case hunk
        case collapsed
    }

    let id = UUID()
    let kind: Kind
    let hunkIndex: Int?
    let left: DiffDisplayRow?
    let right: DiffDisplayRow?

    static func pair(_ rows: [DiffDisplayRow]) -> [SplitDiffPairedRow] {
        var result: [SplitDiffPairedRow] = []
        var index = 0
        var hunkIndex = 0

        while index < rows.count {
            let row = rows[index]

            switch row.kind {
            case .hunk:
                result.append(SplitDiffPairedRow(kind: .hunk, hunkIndex: hunkIndex, left: row, right: nil))
                hunkIndex += 1
                index += 1

            case .collapsed:
                result.append(SplitDiffPairedRow(kind: .collapsed, hunkIndex: hunkIndex - 1, left: row, right: nil))
                index += 1

            case .context:
                result.append(SplitDiffPairedRow(kind: .content, hunkIndex: hunkIndex - 1, left: row, right: row))
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
                for i in 0 ..< maxCount {
                    result.append(SplitDiffPairedRow(
                        kind: .content,
                        hunkIndex: hunkIndex - 1,
                        left: i < deletions.count ? deletions[i] : nil,
                        right: i < additions.count ? additions[i] : nil
                    ))
                }

            case .addition:
                result.append(SplitDiffPairedRow(kind: .content, hunkIndex: hunkIndex - 1, left: nil, right: row))
                index += 1
            }
        }

        return result
    }
}
