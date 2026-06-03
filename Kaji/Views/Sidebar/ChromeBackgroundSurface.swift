import AppKit
import SwiftUI

struct ChromeBackgroundSurface: View {
    @Environment(\.kajiAppearanceContext) private var appearanceContext

    var body: some View {
        TranslucentSurface(
            base: KajiTheme.chrome,
            material: .headerView,
            blendingMode: .behindWindow,
            tintOpacity: AppearanceTransparencyStyle.chromeTintOpacity(
                enabled: appearanceContext.effectiveMode.usesSoftSurfaces,
                amount: appearanceContext.transparencyAmount
            )
        )
    }
}
