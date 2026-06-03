import SwiftUI

extension View {
    @ViewBuilder
    func kajiGlassEffectScope(spacing: CGFloat? = nil) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                self
            }
        } else {
            self
        }
        #else
        self
        #endif
    }
}
