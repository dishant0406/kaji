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
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .kajiFont(size: 12, design: monospaced ? .monospaced : .default)
                    .foregroundStyle(KajiTheme.fgDim)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $text)
                .kajiFont(size: 12, design: monospaced ? .monospaced : .default)
                .foregroundStyle(KajiTheme.fg)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .focused($isFocused)
                .onKeyPress(.return, phases: .down) { keyPress in
                    if keyPress.modifiers.contains(.shift), let onShiftEnter {
                        onShiftEnter()
                        return .handled
                    }
                    if !keyPress.modifiers.contains(.shift), let onSubmit {
                        onSubmit()
                        return .handled
                    }
                    guard keyPress.modifiers.contains(.command), let onCommandEnter else {
                        return .ignored
                    }
                    onCommandEnter()
                    return .handled
                }
        }
        .frame(minHeight: minHeight, maxHeight: maxHeight)
        .background(controlBackground, in: RoundedRectangle(cornerRadius: KajiShape.controlRadius))
        .overlay(
            RoundedRectangle(cornerRadius: KajiShape.controlRadius)
                .stroke(isFocused ? KajiTheme.accent.opacity(0.55) : KajiTheme.borderStrong.opacity(0.9), lineWidth: 1)
        )
    }

    private var controlBackground: Color {
        transparencyEnabled ? KajiTheme.secondaryBackground.opacity(0.46) : KajiTheme.secondaryBackground
    }
}
