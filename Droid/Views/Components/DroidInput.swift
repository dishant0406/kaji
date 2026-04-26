import SwiftUI

struct DroidInput: View {
    let placeholder: String
    @Binding var text: String
    var leadingIcon: String?
    var width: CGFloat?
    var monospaced = false
    @AppStorage(AppearanceSettingsKeys.sidebarTransparencyEnabled) private var transparencyEnabled = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            if let leadingIcon {
                DroidIcon(systemName: leadingIcon, size: 12)
                    .foregroundStyle(isFocused ? DroidTheme.fg : DroidTheme.fgDim)
            }

            TextField(
                "",
                text: $text,
                prompt: Text(placeholder).foregroundStyle(DroidTheme.fgDim)
            )
            .textFieldStyle(.plain)
            .font(inputFont)
            .foregroundStyle(DroidTheme.fg)
            .focused($isFocused)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: width, alignment: .leading)
        .background(controlBackground, in: RoundedRectangle(cornerRadius: DroidShape.tileRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DroidShape.tileRadius)
                .stroke(isFocused ? DroidTheme.accent.opacity(0.6) : DroidTheme.border, lineWidth: 1)
        )
    }

    private var inputFont: Font {
        monospaced
            ? .system(size: 12, weight: .regular, design: .monospaced)
            : .system(size: 12, weight: .regular)
    }

    private var controlBackground: Color {
        transparencyEnabled ? DroidTheme.surface.opacity(0.5) : DroidTheme.surface
    }
}
