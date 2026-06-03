import SwiftUI

struct KajiControlSurface: View {
    let base: Color
    var cornerRadius: CGFloat
    var isInteractive = false
    @Environment(\.kajiAppearanceContext) private var appearanceContext

    var body: some View {
        Group {
            if effectiveMode == .glass {
                if #available(macOS 26.0, *) {
                    let material = Glass.regular.tint(base.opacity(0.15))
                    let config = isInteractive ? material.interactive() : material
                    base.opacity(0.03)
                        .glassEffect(config, in: .rect(cornerRadius: cornerRadius))
                } else {
                    base.opacity(0.03)
                }
            } else {
                base
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var effectiveMode: EffectiveAppearanceMode {
        appearanceContext.effectiveMode
    }
}
