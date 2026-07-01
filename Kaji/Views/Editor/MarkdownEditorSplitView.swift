import Bonsplit
import SwiftUI

struct MarkdownEditorSplitView<Code: View, Preview: View>: View {
    @Binding var ratio: CGFloat
    let code: Code
    let preview: Preview

    init(
        ratio: Binding<CGFloat>,
        @ViewBuilder code: () -> Code,
        @ViewBuilder preview: () -> Preview
    ) {
        _ratio = ratio
        self.code = code()
        self.preview = preview()
    }

    var body: some View {
        BonsplitSplitView(
            direction: .horizontal,
            ratio: ratio,
            minimumPaneSize: 320,
            onRatioChange: { ratio = $0 },
            first: { code },
            second: { preview }
        )
    }
}
