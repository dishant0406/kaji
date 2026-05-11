import AppKit
import SwiftUI

struct TranslucentSurface: View {
    let base: Color
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var tintOpacity: Double = 0.72
    var gradientOpacity: Double = 0
    var isEmphasized = false
    @AppStorage(AppearanceSettingsKeys.sidebarTransparencyEnabled) private var transparencyEnabled = false
    @AppStorage(AppearanceSettingsKeys.interfaceTransparencyAmount) private var transparencyAmount = 0.7
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if transparencyEnabled, !reduceTransparency {
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

    private var adjustedTintOpacity: Double {
        AppearanceTransparencyStyle.adjustedTintOpacity(
            baseTintOpacity: tintOpacity,
            amount: transparencyAmount
        )
    }

    private var adjustedGradientOpacity: Double {
        AppearanceTransparencyStyle.adjustedGradientOpacity(
            baseGradientOpacity: gradientOpacity,
            amount: transparencyAmount
        )
    }
}
