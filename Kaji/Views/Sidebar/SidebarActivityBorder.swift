import SwiftUI

struct SidebarActivityBorder: View {
    let cornerRadius: CGFloat
    let lineWidth: CGFloat

    @State private var angle = 0.0

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .strokeBorder(gradient, lineWidth: lineWidth)
            .shadow(color: KajiTheme.accent.opacity(0.16), radius: 4)
            .onAppear {
                guard angle == 0 else { return }
                withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            }
    }

    private var gradient: AngularGradient {
        AngularGradient(
            gradient: Gradient(stops: [
                .init(color: KajiTheme.accent.opacity(0), location: 0),
                .init(color: KajiTheme.accent.opacity(0), location: 0.56),
                .init(color: KajiTheme.accent.opacity(0.18), location: 0.68),
                .init(color: KajiTheme.accent.opacity(0.95), location: 0.76),
                .init(color: KajiTheme.accent.opacity(0.22), location: 0.84),
                .init(color: KajiTheme.accent.opacity(0), location: 0.94),
                .init(color: KajiTheme.accent.opacity(0), location: 1),
            ]),
            center: .center,
            angle: .degrees(angle)
        )
    }
}
