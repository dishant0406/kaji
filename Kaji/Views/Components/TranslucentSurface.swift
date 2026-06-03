import AppKit
import SwiftUI

struct TranslucentSurface: View {
    let base: Color
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var tintOpacity: Double = 0.72
    var gradientOpacity: Double = 0
    var isEmphasized = false
    var glassCornerRadius: CGFloat = 0
    @Environment(\.kajiAppearanceContext) private var appearanceContext

    var body: some View {
        Group {
            if effectiveMode == .glass {
                if #available(macOS 26.0, *) {
                    base.opacity(adjustedGlassSurfaceTint)
                        .glassEffect(.regular, in: .rect(cornerRadius: glassCornerRadius))
                } else {
                    base.opacity(adjustedGlassSurfaceTint)
                }
            } else if effectiveMode == .translucent {
                ZStack {
                    MaterialBackgroundView(
                        material: material,
                        blendingMode: blendingMode,
                        isEmphasized: isEmphasized
                    )
                    Rectangle().fill(base.opacity(adjustedTintOpacity))
                    if gradientOpacity > 0 {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        base.opacity(adjustedGradientOpacity),
                                        base.opacity(adjustedGradientOpacity * 0.35),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                }
            } else {
                base
            }
        }
    }

    private var effectiveMode: EffectiveAppearanceMode {
        appearanceContext.effectiveMode
    }

    private var adjustedTintOpacity: Double {
        AppearanceTransparencyStyle.adjustedTintOpacity(
            baseTintOpacity: tintOpacity,
            amount: appearanceContext.transparencyAmount
        )
    }

    private var adjustedGradientOpacity: Double {
        AppearanceTransparencyStyle.adjustedGradientOpacity(
            baseGradientOpacity: gradientOpacity,
            amount: appearanceContext.transparencyAmount
        )
    }

    private var adjustedGlassSurfaceTint: Double {
        if glassCornerRadius == 0 { return 0.04 }
        return max(0.06, adjustedTintOpacity * 0.12)
    }
}
