import AppKit
import SwiftUI

struct TranslucentSurface: View {
    let base: Color
    var material: NSVisualEffectView.Material = .hudWindow
    var tintOpacity: Double = 0.72
    var gradientOpacity: Double = 0
    @AppStorage(AppearanceSettingsKeys.sidebarTransparencyEnabled) private var transparencyEnabled = false

    var body: some View {
        Group {
            if transparencyEnabled {
                ZStack {
                    SidebarMaterialView(material: material)
                    Rectangle().fill(base.opacity(tintOpacity))
                    if gradientOpacity > 0 {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        base.opacity(gradientOpacity),
                                        base.opacity(gradientOpacity * 0.35),
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
}
