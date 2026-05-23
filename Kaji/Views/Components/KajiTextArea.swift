import SwiftUI

struct KajiTextArea: View {
    let placeholder: String
    @Binding var text: String
    var minHeight: CGFloat = 88
    var maxHeight: CGFloat?
    var monospaced = false
    var onSubmit: (() -> Void)?
    var onShiftEnter: (() -> Void)?
    var onCommandEnter: (() -> Void)?
    @AppStorage(AppearanceSettingsKeys.sidebarTransparencyEnabled) private var transparencyEnabled = false
    @FocusState private var isFocused: Bool

    var body: some View {
        KajiTextAreaRepresentable(
            placeholder: placeholder,
            text: $text,
            isFocused: Binding(
                get: { isFocused },
                set: { isFocused = $0 }
            ),
            monospaced: monospaced,
            onSubmit: onSubmit,
            onShiftEnter: onShiftEnter,
            onCommandEnter: onCommandEnter
        )
        .frame(minHeight: minHeight, maxHeight: maxHeight)
        .background(controlBackground, in: RoundedRectangle(cornerRadius: KajiShape.controlRadius))
        .overlay(
            RoundedRectangle(cornerRadius: KajiShape.controlRadius)
                .stroke(isFocused ? KajiTheme.accent.opacity(0.55) : KajiTheme.borderStrong.opacity(0.9), lineWidth: 1)
        )
        .onTapGesture {
            isFocused = true
        }
    }

    private var controlBackground: Color {
        transparencyEnabled ? KajiTheme.secondaryBackground.opacity(0.46) : KajiTheme.secondaryBackground
    }
}
