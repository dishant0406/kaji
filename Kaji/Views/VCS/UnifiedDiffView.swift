import SwiftUI

struct UnifiedDiffView: View {
    let rows: [DiffDisplayRow]
    let renderPlan: DiffRenderPlan
    let filePath: String
    var onViewMore: ((Int, DiffContextExpansionDirection) -> Void)?
    var contextExpansion: ((Int) -> DiffHunkContextExpansion)?
    var fileLineCount: Int?
    var onCommentRequest: ((DiffCommentAnchor, CGPoint) -> Void)?
    var comments: [DiffComment] = []
    var suppressLeadingTopBorder: Bool = false

    private var chunks: [UnifiedDiffRenderChunk] {
        renderPlan.unifiedChunks
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
                    unifiedCodeBlock(block)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Unified diff, \(filePath)")
    }

    private var gutterWidth: CGFloat {
        numberColumnWidth * 2 + 2 + DiffGutterNSView.prefixColumnWidth
    }

    private func unifiedCodeBlock(_ block: DiffRenderCodeBlock) -> some View {
        let height = CGFloat(block.rows.count) * diffLineHeight
        let metadata = buildDiffMetadata(from: block.rows)
        return ZStack(alignment: .leading) {
            HStack(alignment: .top, spacing: 0) {
                DiffGutterBridge(
                    metadata: metadata,
                    filePath: filePath,
                    mode: .unified,
                    columnWidth: numberColumnWidth,
                    onCommentRequest: onCommentRequest,
                    comments: comments
                )
                .frame(width: gutterWidth + DiffGutterNSView.commentBubbleMaxWidth, height: height, alignment: .leading)
                .frame(width: gutterWidth, height: height, alignment: .leading)
                .zIndex(2)

                ScrollView(.horizontal, showsIndicators: false) {
                    DiffContentBridge(
                        rows: block.rows,
                        backgroundSide: .both,
                        signature: block.signature,
                        maxDisplayColumns: block.maxDisplayColumns
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
            .frame(width: gutterWidth + 120, alignment: .leading)
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
