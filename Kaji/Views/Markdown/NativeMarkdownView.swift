import MarkdownUI
import SwiftUI

struct NativeMarkdownView: View {
    let content: String
    var filePath: String?
    var bodyFontSize: CGFloat = 14

    private var segments: [NativeMarkdownSegment] {
        NativeMarkdownSegmenter.segments(from: content)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(segments) { segment in
                    segmentView(segment)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(KajiTheme.bg)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func segmentView(_ segment: NativeMarkdownSegment) -> some View {
        switch segment.kind {
        case .markdown:
            markdown(segment.content)
        case let .managedBlock(title):
            managedBlock(title: title, content: segment.content)
        }
    }

    private func markdown(_ content: String) -> some View {
        Markdown(content)
            .markdownTheme(kajiTheme)
            .markdownCodeSyntaxHighlighter(.plainText)
    }

    private func managedBlock(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                KajiIcon(systemName: "puzzlepiece.extension", size: 13)
                    .foregroundStyle(KajiTheme.accent)
                Text(title.capitalized)
                    .kajiFont(size: 12, weight: .semibold)
                    .foregroundStyle(KajiTheme.fg)
                Spacer(minLength: 0)
                Text("Managed block")
                    .kajiFont(size: 10, weight: .medium)
                    .foregroundStyle(KajiTheme.fgDim)
            }
            markdown(content)
        }
        .padding(14)
        .background(KajiTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).stroke(KajiTheme.border, lineWidth: 1)
        }
    }

    private var kajiTheme: Theme {
        Theme()
            .text {
                ForegroundColor(KajiTheme.fg)
                BackgroundColor(KajiTheme.bg)
                FontSize(bodyFontSize)
            }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.88))
                ForegroundColor(KajiTheme.fg)
                BackgroundColor(KajiTheme.secondaryBackground)
            }
            .strong { FontWeight(.semibold) }
            .link { ForegroundColor(KajiTheme.accent) }
            .heading1 { heading($0, size: 1.9, divider: true) }
            .heading2 { heading($0, size: 1.45, divider: true) }
            .heading3 { heading($0, size: 1.2, divider: false) }
            .heading4 { heading($0, size: 1.05, divider: false) }
            .heading5 { heading($0, size: 0.95, divider: false) }
            .heading6 { heading($0, size: 0.9, divider: false, muted: true) }
            .paragraph { configuration in
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.25))
                    .markdownMargin(top: 0, bottom: 14)
            }
            .blockquote { configuration in
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(KajiTheme.border)
                        .relativeFrame(width: .em(0.18))
                    configuration.label
                        .markdownTextStyle { ForegroundColor(KajiTheme.fgMuted) }
                        .relativePadding(.horizontal, length: .em(1))
                }
                .fixedSize(horizontal: false, vertical: true)
                .markdownMargin(top: 0, bottom: 14)
            }
            .codeBlock { configuration in
                ScrollView(.horizontal) {
                    configuration.label
                        .fixedSize(horizontal: false, vertical: true)
                        .relativeLineSpacing(.em(0.25))
                        .markdownTextStyle {
                            FontFamilyVariant(.monospaced)
                            FontSize(.em(0.9))
                            ForegroundColor(KajiTheme.fg)
                            BackgroundColor(nil)
                        }
                        .padding(14)
                }
                .background(KajiTheme.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8).stroke(KajiTheme.border, lineWidth: 1)
                }
                .markdownMargin(top: 0, bottom: 14)
            }
            .listItem { configuration in
                configuration.label.markdownMargin(top: .em(0.2))
            }
            .table { configuration in
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .markdownTableBorderStyle(.init(color: KajiTheme.border))
                    .markdownTableBackgroundStyle(.alternatingRows(KajiTheme.bg, KajiTheme.secondaryBackground))
                    .markdownMargin(top: 0, bottom: 14)
            }
            .tableCell { configuration in
                configuration.label
                    .markdownTextStyle {
                        if configuration.row == 0 { FontWeight(.semibold) }
                        ForegroundColor(KajiTheme.fg)
                        BackgroundColor(nil)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .relativeLineSpacing(.em(0.2))
            }
            .thematicBreak {
                Rectangle()
                    .fill(KajiTheme.border)
                    .frame(height: 1)
                    .markdownMargin(top: 20, bottom: 20)
            }
    }

    private func heading(_ configuration: BlockConfiguration, size: CGFloat, divider: Bool, muted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            configuration.label
                .relativeLineSpacing(.em(0.125))
                .markdownMargin(top: 20, bottom: divider ? 8 : 6)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(size))
                    ForegroundColor(muted ? KajiTheme.fgMuted : KajiTheme.fg)
                }
            if divider {
                Rectangle().fill(KajiTheme.border).frame(height: 1)
            }
        }
    }
}
