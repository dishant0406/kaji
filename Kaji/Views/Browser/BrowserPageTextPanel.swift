import SwiftUI

struct BrowserPageTextPanel: View {
    let title: String
    let text: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(KajiTheme.fg)
                Spacer()
                IconButton(symbol: "xmark", accessibilityLabel: "Close page text", action: onClose)
            }
            ScrollView {
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(KajiTheme.fg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .frame(maxHeight: 220)
        .padding(12)
        .background(KajiTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: KajiShape.panelRadius))
        .overlay(RoundedRectangle(cornerRadius: KajiShape.panelRadius).stroke(KajiTheme.border))
        .padding(12)
    }
}
