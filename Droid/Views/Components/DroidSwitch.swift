import SwiftUI

struct DroidSwitch: View {
    @Binding var isOn: Bool
    @AppStorage(AppearanceSettingsKeys.sidebarTransparencyEnabled) private var transparencyEnabled = false
    private let animation = Animation.easeInOut(duration: 0.16)

    var body: some View {
        Button {
            withAnimation(animation) {
                isOn.toggle()
            }
        } label: {
            RoundedRectangle(cornerRadius: DroidShape.controlRadius)
                .fill(trackColor)
                .overlay(
                    RoundedRectangle(cornerRadius: DroidShape.controlRadius)
                        .stroke(isOn ? DroidTheme.accent.opacity(0.45) : DroidTheme.border, lineWidth: 1)
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
        .droidPointer()
        .accessibilityLabel(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
        .accessibilityRepresentation {
            Toggle("", isOn: $isOn)
        }
    }

    private var trackColor: Color {
        if isOn {
            return transparencyEnabled ? DroidTheme.accentSoft.opacity(0.68) : DroidTheme.accentSoft
        }
        return transparencyEnabled ? DroidTheme.surface.opacity(0.5) : DroidTheme.surface
    }

    private var knobColor: Color {
        if isOn {
            return transparencyEnabled ? DroidTheme.accent.opacity(0.92) : DroidTheme.accent
        }
        return transparencyEnabled ? DroidTheme.fgDim.opacity(0.9) : DroidTheme.fgDim
    }
}
