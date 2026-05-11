import SwiftUI

struct MarkdownInlineText: View {
    let content: String
    var size: CGFloat = 13
    var color: Color = KajiTheme.fgMuted

    var body: some View {
        Text(attributedContent)
            .kajiFont(size: size)
            .foregroundStyle(color)
            .textSelection(.enabled)
    }

    private var attributedContent: AttributedString {
        let parsed = try? AttributedString(markdown: content)
        return parsed ?? AttributedString(content)
    }
}
