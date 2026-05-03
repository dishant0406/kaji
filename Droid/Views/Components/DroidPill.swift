import SwiftUI

enum DroidPillVariant {
    case plain
    case filled
    case bordered
}

struct DroidPill: View {
    let title: String
    var leadingIcon: String?
    var trailingIcon: String?
    var variant: DroidPillVariant = .filled
    var selected = false
    var disabled = false
    var width: CGFloat?
    var action: (() -> Void)?
    @State private var hovered = false

    var body: some View {
        Button(action: { action?() }, label: {
            HStack(spacing: 6) {
                if let leadingIcon {
                    DroidIcon(systemName: leadingIcon, size: 11)
                }
                Text(title)
                    .lineLimit(1)
                if let trailingIcon {
                    DroidIcon(systemName: trailingIcon, size: 9)
                }
            }
            .droidFont(size: 12, weight: .medium)
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(width: width)
            .background(background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(border, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        })
        .buttonStyle(.plain)
        .disabled(disabled || action == nil)
        .onHover { hovered = $0 }
    }

    private var foreground: Color {
        if disabled { return DroidTheme.fgDim.opacity(0.6) }
        if selected || hovered { return DroidTheme.fg }
        return DroidTheme.fgMuted
    }

    private var background: Color {
        switch variant {
        case .plain:
            hovered || selected ? DroidTheme.hover.opacity(0.55) : .clear
        case .filled:
            hovered || selected ? DroidTheme.surface : DroidTheme.secondaryBackground
        case .bordered:
            hovered || selected ? DroidTheme.hover.opacity(0.45) : .clear
        }
    }

    private var border: Color {
        switch variant {
        case .plain:
            .clear
        case .filled:
            selected ? DroidTheme.borderStrong : .clear
        case .bordered:
            hovered || selected ? DroidTheme.borderStrong : DroidTheme.border
        }
    }
}
