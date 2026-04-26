import SwiftUI

enum DroidButtonVariant {
    case primary
    case secondary
    case ghost
    case danger
}

enum DroidButtonSize {
    case regular
    case small

    var horizontalPadding: CGFloat {
        switch self {
        case .regular:
            12
        case .small:
            10
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .regular:
            7
        case .small:
            5
        }
    }

    var baseFontSize: CGFloat {
        switch self {
        case .regular:
            12
        case .small:
            11
        }
    }
}

struct DroidButtonStyle: ButtonStyle {
    let variant: DroidButtonVariant
    let size: DroidButtonSize
    @AppStorage(AppearanceSettingsKeys.sidebarTransparencyEnabled) private var transparencyEnabled = false

    init(_ variant: DroidButtonVariant = .secondary, size: DroidButtonSize = .regular) {
        self.variant = variant
        self.size = size
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .droidFont(size: size.baseFontSize, weight: .medium)
            .foregroundStyle(foregroundColor(isPressed: configuration.isPressed))
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .background(
                backgroundColor(isPressed: configuration.isPressed),
                in: RoundedRectangle(cornerRadius: DroidShape.tileRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DroidShape.tileRadius)
                    .stroke(borderColor(isPressed: configuration.isPressed), lineWidth: 1)
            )
    }

    private func foregroundColor(isPressed: Bool) -> Color {
        switch variant {
        case .primary:
            return DroidTheme.bg
        case .secondary:
            return DroidTheme.fg
        case .ghost:
            return isPressed ? DroidTheme.fg : DroidTheme.fgMuted
        case .danger:
            return DroidTheme.diffRemoveFg
        }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        switch variant {
        case .primary:
            return isPressed
                ? DroidTheme.accent.opacity(transparencyEnabled ? 0.76 : 0.82)
                : DroidTheme.accent.opacity(transparencyEnabled ? 0.88 : 1)
        case .secondary:
            if isPressed {
                return transparencyEnabled ? DroidTheme.hover.opacity(0.54) : DroidTheme.hover
            }
            return transparencyEnabled ? DroidTheme.surface.opacity(0.52) : DroidTheme.surface
        case .ghost:
            if isPressed {
                return transparencyEnabled ? DroidTheme.hover.opacity(0.48) : DroidTheme.hover
            }
            return transparencyEnabled ? DroidTheme.bg.opacity(0.18) : DroidTheme.bg
        case .danger:
            return isPressed
                ? DroidTheme.diffRemoveBg.opacity(transparencyEnabled ? 0.56 : 0.82)
                : DroidTheme.diffRemoveBg.opacity(transparencyEnabled ? 0.42 : 1)
        }
    }

    private func borderColor(isPressed: Bool) -> Color {
        switch variant {
        case .primary:
            return DroidTheme.accent.opacity(isPressed ? 0.9 : 0.75)
        case .secondary:
            return DroidTheme.border
        case .ghost:
            return isPressed ? DroidTheme.border : .clear
        case .danger:
            return DroidTheme.diffRemoveFg.opacity(0.35)
        }
    }
}
