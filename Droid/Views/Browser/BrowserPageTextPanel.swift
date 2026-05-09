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
                    .foregroundStyle(DroidTheme.fg)
                Spacer()
                IconButton(symbol: "xmark", accessibilityLabel: "Close page text", action: onClose)
            }
            ScrollView {
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(DroidTheme.fg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .frame(maxHeight: 220)
        .padding(12)
        .background(DroidTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: DroidShape.panelRadius))
        .overlay(RoundedRectangle(cornerRadius: DroidShape.panelRadius).stroke(DroidTheme.border))
        .padding(12)
    }
}
