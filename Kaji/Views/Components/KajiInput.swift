import SwiftUI

struct KajiInput: View {
    let placeholder: String
    @Binding var text: String
    var leadingIcon: String?
    var width: CGFloat?
    var monospaced = false
    @Environment(\.kajiAppearanceContext) private var appearanceContext
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            if let leadingIcon {
                KajiIcon(systemName: leadingIcon, size: 12)
                    .foregroundStyle(isFocused ? KajiTheme.fg : KajiTheme.fgDim)
            }

            TextField(
                "",
                text: $text,
                prompt: Text(placeholder).foregroundStyle(KajiTheme.fgDim)
            )
            .textFieldStyle(.plain)
            .kajiFont(size: 12, design: monospaced ? .monospaced : .default)
            .foregroundStyle(KajiTheme.fg)
            .focused($isFocused)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: width, alignment: .leading)
        .background(
            KajiControlSurface(
                base: controlBackground,
                cornerRadius: KajiShape.tileRadius
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: KajiShape.tileRadius)
                .stroke(isFocused ? KajiTheme.accent.opacity(0.6) : KajiTheme.border, lineWidth: 1)
        )
        .animation(KajiMotion.fast, value: isFocused)
    }

    private var controlBackground: Color {
        if effectiveMode == .glass { return KajiTheme.surface.opacity(isFocused ? 0.32 : 0.22) }
        return effectiveMode.usesSoftSurfaces ? KajiTheme.surface.opacity(0.5) : KajiTheme.surface
    }

    private var effectiveMode: EffectiveAppearanceMode {
        appearanceContext.effectiveMode
    }
}
