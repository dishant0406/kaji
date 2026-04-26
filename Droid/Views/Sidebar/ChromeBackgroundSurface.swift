import AppKit
import SwiftUI

struct ChromeBackgroundSurface: View {
    let transparencyEnabled: Bool

    var body: some View {
        TranslucentSurface(
            base: DroidTheme.chrome,
            material: .headerView,
            tintOpacity: transparencyEnabled ? 0.46 : 1
        )
    }
}
