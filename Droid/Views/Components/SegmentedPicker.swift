import SwiftUI

struct SegmentedPicker<T: Hashable>: View {
    @Binding var selection: T
    let options: [(value: T, label: String)]
    @AppStorage(AppearanceSettingsKeys.sidebarTransparencyEnabled) private var transparencyEnabled = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(.system(size: 11, weight: selection == option.value ? .semibold : .regular))
                        .foregroundStyle(selection == option.value ? DroidTheme.fg : DroidTheme.fgMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            selection == option.value
                                ? activeSegmentBackground
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: DroidShape.badgeRadius)
                        )
                }
                .buttonStyle(.plain)

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
        .background(containerBackground, in: RoundedRectangle(cornerRadius: DroidShape.controlRadius))
        .accessibilityRepresentation {
            Picker(selection: $selection, label: EmptyView()) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    Text(option.label).tag(option.value)
                }
            }
        }
    }

    private var activeSegmentBackground: Color {
        transparencyEnabled ? DroidTheme.surface.opacity(0.54) : DroidTheme.surface
    }

    private var containerBackground: Color {
        transparencyEnabled ? DroidTheme.hover.opacity(0.5) : DroidTheme.hover
    }
}
