import SwiftUI

enum KajiButtonVariant {
    case primary
    case secondary
    case ghost
    case danger
}

enum KajiButtonSize {
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

struct KajiButtonStyle: ButtonStyle {
    let variant: KajiButtonVariant
    let size: KajiButtonSize
    @AppStorage(AppearanceSettingsKeys.sidebarTransparencyEnabled) private var transparencyEnabled = false

    init(_ variant: KajiButtonVariant = .secondary, size: KajiButtonSize = .regular) {
        self.variant = variant
        self.size = size
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .kajiFont(size: size.baseFontSize, weight: .medium)
            .foregroundStyle(foregroundColor(isPressed: configuration.isPressed))
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .background(
                backgroundColor(isPressed: configuration.isPressed),
                in: RoundedRectangle(cornerRadius: KajiShape.tileRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: KajiShape.tileRadius)
                    .stroke(borderColor(isPressed: configuration.isPressed), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: KajiShape.tileRadius))
            .kajiPressEffect(isPressed: configuration.isPressed)
            .kajiPointer()
    }

    private func foregroundColor(isPressed: Bool) -> Color {
        switch variant {
        case .primary:
            KajiTheme.bg
        case .secondary:
            KajiTheme.fg
        case .ghost:
            isPressed ? KajiTheme.fg : KajiTheme.fgMuted
        case .danger:
            KajiTheme.diffRemoveFg
        }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        switch variant {
        case .primary:
            return isPressed
                ? KajiTheme.accent.opacity(transparencyEnabled ? 0.76 : 0.82)
                : KajiTheme.accent.opacity(transparencyEnabled ? 0.88 : 1)
        case .secondary:
            if isPressed {
                return transparencyEnabled ? KajiTheme.hover.opacity(0.54) : KajiTheme.hover
            }
            return transparencyEnabled ? KajiTheme.surface.opacity(0.52) : KajiTheme.surface
        case .ghost:
            if isPressed {
                return transparencyEnabled ? KajiTheme.hover.opacity(0.48) : KajiTheme.hover
            }
            return transparencyEnabled ? KajiTheme.bg.opacity(0.18) : KajiTheme.bg
        case .danger:
            return isPressed
                ? KajiTheme.diffRemoveBg.opacity(transparencyEnabled ? 0.56 : 0.82)
                : KajiTheme.diffRemoveBg.opacity(transparencyEnabled ? 0.42 : 1)
        }
    }

    private func borderColor(isPressed: Bool) -> Color {
        switch variant {
        case .primary:
            KajiTheme.accent.opacity(isPressed ? 0.9 : 0.75)
        case .secondary:
            KajiTheme.border
        case .ghost:
            isPressed ? KajiTheme.border : .clear
        case .danger:
            KajiTheme.diffRemoveFg.opacity(0.35)
        }
    }
}
