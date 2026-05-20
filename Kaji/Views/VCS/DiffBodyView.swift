import SwiftUI

struct DiffBodyView: View {
    let isLoading: Bool
    let error: String?
    let diff: DiffCache.LoadedDiff?
    let filePath: String
    let mode: VCSTabState.ViewMode
    let onLoadFull: (() -> Void)?
    var onViewMore: ((Int, DiffContextExpansionDirection) -> Void)?
    var contextExpansion: ((Int) -> DiffHunkContextExpansion)?
    var onCommentRequest: ((DiffCommentAnchor, CGPoint) -> Void)?
    var comments: [DiffComment] = []
    var suppressLeadingTopBorder: Bool = false

    var body: some View {
        Group {
            if isLoading, diff == nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(14)
            } else if let error {
                Text(error)
                    .kajiFont(size: 12)
                    .foregroundStyle(KajiTheme.fgMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            } else if let diff {
                VStack(spacing: 0) {
                    if diff.truncated, let onLoadFull {
                        truncatedBanner(onLoadFull: onLoadFull)
                        Rectangle().fill(KajiTheme.border).frame(height: 1)
                    }

                    switch mode {
                    case .unified:
                        UnifiedDiffView(
                            rows: diff.rows,
                            filePath: filePath,
                            onViewMore: onViewMore,
                            contextExpansion: contextExpansion,
                            fileLineCount: diff.fileLineCount,
                            onCommentRequest: onCommentRequest,
                            comments: comments,
                            suppressLeadingTopBorder: suppressLeadingTopBorder && !diff.truncated
                        )
                    case .split:
                        SplitDiffView(
                            rows: diff.rows,
                            filePath: filePath,
                            onViewMore: onViewMore,
                            contextExpansion: contextExpansion,
                            fileLineCount: diff.fileLineCount,
                            onCommentRequest: onCommentRequest,
                            comments: comments,
                            suppressLeadingTopBorder: suppressLeadingTopBorder && !diff.truncated
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("No diff output")
                    .kajiFont(size: 12)
                    .foregroundStyle(KajiTheme.fgMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        }
        .background(KajiTheme.bg)
    }

    private func truncatedBanner(onLoadFull: @escaping () -> Void) -> some View {
        HStack {
            Text("Large diff preview")
                .kajiFont(size: 11, weight: .medium)
                .foregroundStyle(KajiTheme.fgMuted)
            Spacer(minLength: 0)
            Button("Load full diff", action: onLoadFull)
                .buttonStyle(.plain)
                .kajiFont(size: 11, weight: .semibold)
                .foregroundStyle(KajiTheme.accent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}
