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
            .droidFont(size: 12, design: monospaced ? .monospaced : .default)
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

    private var controlBackground: Color {
        transparencyEnabled ? DroidTheme.surface.opacity(0.5) : DroidTheme.surface
    }
}
