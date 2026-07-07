import SwiftUI

struct KajiSpinner: View {
    var size: CGFloat = 12
    var lineWidth: CGFloat = 1.6
    var color: Color = KajiTheme.fgMuted
    @State private var rotating = false
    @State private var animationGeneration = 0
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
            .onAppear(perform: restartAnimation)
            .onDisappear(perform: stopAnimation)
            .onChange(of: shouldAnimate) { _, _ in restartAnimation() }
    }

    private var shouldAnimate: Bool {
        KajiSpinnerAnimationPolicy.shouldAnimate(reduceMotion: reduceMotion)
    }

    private func restartAnimation() {
        animationGeneration += 1
        let generation = animationGeneration
        rotating = false
        guard shouldAnimate else { return }
        Task { @MainActor in
            await Task.yield()
            guard animationGeneration == generation, shouldAnimate else { return }
            withAnimation(.linear(duration: KajiSpinnerAnimationPolicy.duration).repeatForever(autoreverses: false)) {
                rotating = true
            }
        }
    }

    private func stopAnimation() {
        animationGeneration += 1
        rotating = false
    }
}
