import SwiftUI

struct SidebarBackgroundSurface: View {
    @Environment(\.kajiAppearanceContext) private var appearanceContext

    var body: some View {
        TranslucentSurface(
            base: KajiTheme.secondaryBackground,
            material: .sidebar,
            blendingMode: .behindWindow,
            tintOpacity: AppearanceTransparencyStyle.sidebarTintOpacity(
                enabled: appearanceContext.effectiveMode.usesSoftSurfaces,
                amount: appearanceContext.transparencyAmount
            ),
            gradientOpacity: AppearanceTransparencyStyle.sidebarGradientOpacity(
                enabled: appearanceContext.effectiveMode.usesSoftSurfaces,
                amount: appearanceContext.transparencyAmount
            )
        )
    }
}
