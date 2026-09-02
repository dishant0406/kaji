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
                    let material = Glass.regular.tint(base.opacity(0.18))
                    let config = isInteractive ? material.interactive() : material
                    legibleGlassTint(base: base)
                        .glassEffect(config, in: .rect(cornerRadius: cornerRadius))
                } else {
                    legibleTint(base: base)
                }
            } else {
                base
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private func legibleGlassTint(base: Color) -> some View {
        ZStack {
            base
            KajiTheme.bg.opacity(0.34)
        }
    }

    private func legibleTint(base: Color) -> some View {
        ZStack {
            base
            KajiTheme.bg.opacity(0.55)
        }
    }

    private var effectiveMode: EffectiveAppearanceMode {
        appearanceContext.effectiveMode
    }
}
