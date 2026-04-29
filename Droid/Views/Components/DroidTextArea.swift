import SwiftUI

struct DroidTextArea: View {
    let placeholder: String
    @Binding var text: String
    var minHeight: CGFloat = 88
    var maxHeight: CGFloat?
    var monospaced = false
    var onSubmit: (() -> Void)?
    var onCommandEnter: (() -> Void)?
    @AppStorage(AppearanceSettingsKeys.sidebarTransparencyEnabled) private var transparencyEnabled = false
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .droidFont(size: 12, design: monospaced ? .monospaced : .default)
                    .foregroundStyle(DroidTheme.fgDim)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $text)
                .droidFont(size: 12, design: monospaced ? .monospaced : .default)
                .foregroundStyle(DroidTheme.fg)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .focused($isFocused)
                .onKeyPress(.return, phases: .down) { keyPress in
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
        .background(controlBackground, in: RoundedRectangle(cornerRadius: DroidShape.controlRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DroidShape.controlRadius)
                .stroke(isFocused ? DroidTheme.accent.opacity(0.55) : DroidTheme.borderStrong.opacity(0.9), lineWidth: 1)
        )
    }

    private var controlBackground: Color {
        transparencyEnabled ? DroidTheme.secondaryBackground.opacity(0.46) : DroidTheme.secondaryBackground
    }
}
