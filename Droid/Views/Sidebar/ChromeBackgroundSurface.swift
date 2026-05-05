import AppKit
import SwiftUI

struct ChromeBackgroundSurface: View {
    let transparencyEnabled: Bool
    let transparencyAmount: Double

    var body: some View {
        TranslucentSurface(
            base: DroidTheme.chrome,
            material: .headerView,
            blendingMode: .behindWindow,
            tintOpacity: AppearanceTransparencyStyle.chromeTintOpacity(
                enabled: transparencyEnabled,
                amount: transparencyAmount
            )
        )
    }
}
