import SwiftUI

struct SidebarBackgroundSurface: View {
    let transparencyEnabled: Bool
    let transparencyAmount: Double

    var body: some View {
        TranslucentSurface(
            base: KajiTheme.secondaryBackground,
            material: .sidebar,
            blendingMode: .behindWindow,
            tintOpacity: AppearanceTransparencyStyle.sidebarTintOpacity(
                enabled: transparencyEnabled,
                amount: transparencyAmount
            ),
            gradientOpacity: AppearanceTransparencyStyle.sidebarGradientOpacity(
                enabled: transparencyEnabled,
                amount: transparencyAmount
            )
        )
    }
}
