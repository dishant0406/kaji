import SwiftUI

struct KajiSwitch: View {
    @Binding var isOn: Bool
    @AppStorage(AppearanceSettingsKeys.sidebarTransparencyEnabled) private var transparencyEnabled = false
    private let animation = Animation.easeInOut(duration: 0.16)

    var body: some View {
        Button {
            withAnimation(animation) {
                isOn.toggle()
            }
        } label: {
            RoundedRectangle(cornerRadius: KajiShape.controlRadius)
                .fill(trackColor)
                .overlay(
                    RoundedRectangle(cornerRadius: KajiShape.controlRadius)
                        .stroke(isOn ? KajiTheme.accent.opacity(0.45) : KajiTheme.border, lineWidth: 1)
                )
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(knobColor)
                        .frame(width: 12, height: 12)
                        .offset(x: isOn ? 16 : 0)
                        .padding(3)
                }
                .frame(width: 34, height: 18)
                .animation(animation, value: isOn)
        }
        .buttonStyle(.plain)
        .kajiPointer()
        .accessibilityLabel(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
        .accessibilityRepresentation {
            Toggle("", isOn: $isOn)
        }
    }

    private var trackColor: Color {
        if isOn {
            return transparencyEnabled ? KajiTheme.accentSoft.opacity(0.68) : KajiTheme.accentSoft
        }
        return transparencyEnabled ? KajiTheme.surface.opacity(0.5) : KajiTheme.surface
    }

    private var knobColor: Color {
        if isOn {
            return transparencyEnabled ? KajiTheme.accent.opacity(0.92) : KajiTheme.accent
        }
        return transparencyEnabled ? KajiTheme.fgDim.opacity(0.9) : KajiTheme.fgDim
    }
}
