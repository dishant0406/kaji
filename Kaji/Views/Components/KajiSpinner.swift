import SwiftUI

struct KajiSpinner: View {
    var size: CGFloat = 12
    var lineWidth: CGFloat = 1.6
    var color: Color = KajiTheme.fgMuted
    @State private var rotating = false
    @State private var settings = TerminalSettingsStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .trim(from: 0.16, to: 0.82)
            .stroke(
                color,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .frame(width: size, height: size)
            .rotationEffect(.degrees(rotating ? 360 : 0))
            .onAppear {
                guard shouldAnimate else { return }
                withAnimation(.linear(duration: 0.85).repeatForever(autoreverses: false)) {
                    rotating = true
                }
            }
            .onChange(of: shouldAnimate) { _, animate in
                rotating = false
                guard animate else { return }
                withAnimation(.linear(duration: 0.85).repeatForever(autoreverses: false)) {
                    rotating = true
                }
            }
    }

    private var shouldAnimate: Bool {
        !reduceMotion && !settings.batteryOptimizedMode
    }
}
