import SwiftUI

struct SegmentedPicker<T: Hashable>: View {
    @Binding var selection: T
    let options: [(value: T, label: String)]
    @Environment(\.kajiAppearanceContext) private var appearanceContext

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button {
                    withAnimation(KajiMotion.select) {
                        selection = option.value
                    }
                } label: {
                    Text(option.label)
                        .kajiFont(size: 11, weight: selection == option.value ? .semibold : .regular)
                        .foregroundStyle(selection == option.value ? KajiTheme.fg : KajiTheme.fgMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            selection == option.value
                                ? activeSegmentBackground
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: KajiShape.badgeRadius)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .kajiChangeFeedback(KajiMotion.selectionFeedback, value: selection == option.value, isEnabled: selection == option.value)
                .kajiPointer()

                if index < options.count - 1, selection != option.value,
                   selection != options[index + 1].value
                {
                    Divider()
                        .frame(height: 14)
                        .opacity(0.4)
                }
            }
        }
        .padding(2)
        .background(
            KajiControlSurface(
                base: containerBackground,
                cornerRadius: KajiShape.controlRadius
            )
        )
        .accessibilityRepresentation {
            Picker(selection: $selection, label: EmptyView()) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    Text(option.label).tag(option.value)
                }
            }
        }
    }

    private var activeSegmentBackground: Color {
        if effectiveMode == .glass {
            return KajiTheme.surface.opacity(0.28)
        }
        return effectiveMode.usesSoftSurfaces ? KajiTheme.surface.opacity(0.54) : KajiTheme.surface
    }

    private var containerBackground: Color {
        if effectiveMode == .glass {
            return KajiTheme.hover.opacity(0.22)
        }
        return effectiveMode.usesSoftSurfaces ? KajiTheme.hover.opacity(0.5) : KajiTheme.hover
    }

    private var effectiveMode: EffectiveAppearanceMode {
        appearanceContext.effectiveMode
    }
}
