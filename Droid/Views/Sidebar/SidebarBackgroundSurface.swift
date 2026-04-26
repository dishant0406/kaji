import SwiftUI

struct SidebarBackgroundSurface: View {
    let transparencyEnabled: Bool

    var body: some View {
        TranslucentSurface(
            base: DroidTheme.secondaryBackground,
            material: .sidebar,
            tintOpacity: transparencyEnabled ? 0.5 : 1,
            gradientOpacity: transparencyEnabled ? 0.22 : 0
        )
    }
}
