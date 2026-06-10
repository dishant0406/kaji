import SwiftUI

struct KajiAgentInlineText: View {
    let content: String
    var size: CGFloat = 14
    var color: Color = KajiTheme.fg

    var body: some View {
        renderedText
            .lineSpacing(3)
            .textSelection(.enabled)
    }

    private var renderedText: Text {
        KajiAgentInlineSemanticParser.tokens(from: content).reduce(Text("")) { partial, token in
            partial + text(for: token)
        }
    }

    private func text(for token: KajiAgentInlineToken) -> Text {
        switch token {
        case let .text(value):
            Text(value).foregroundStyle(color)
        case let .strong(value):
            Text(value).fontWeight(.semibold).foregroundStyle(color)
        case let .emphasis(value):
            Text(value).italic().foregroundStyle(color)
        case let .inlineCode(value):
            Text(value).font(.system(size: max(11, size - 1), design: .monospaced)).foregroundStyle(KajiTheme.accent)
        case let .link(title, _):
            Text(title).underline().foregroundStyle(KajiTheme.accent)
        case let .image(alt, source):
            Text("[Image: \(alt.nilIfEmpty ?? source)]").foregroundStyle(KajiTheme.diffHunkFg)
        case let .filePath(value):
            Text(value).font(.system(size: max(11, size - 1), design: .monospaced)).foregroundStyle(KajiTheme.diffHunkFg)
        case let .command(value):
            Text(value).font(.system(size: max(11, size - 1), design: .monospaced)).foregroundStyle(KajiTheme.diffAddFg)
        case let .symbol(value):
            Text(value).font(.system(size: max(11, size - 1), design: .monospaced)).foregroundStyle(KajiTheme.fg)
        }
    }
}
