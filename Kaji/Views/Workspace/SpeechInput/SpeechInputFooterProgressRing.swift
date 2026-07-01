import SwiftUI

struct SpeechInputFooterProgressRing: View {
    let progress: SpeechDownloadProgress?
    @State private var rotating = false
    @State private var settings = TerminalSettingsStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(KajiTheme.border.opacity(0.75), lineWidth: 1.3)
            Circle()
                .trim(from: 0, to: progress?.clampedFraction ?? 0.72)
                .stroke(KajiTheme.accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(progress == nil ? (rotating ? 360 : 0) : -90))
                .animation(.easeOut(duration: 0.16), value: progress?.clampedFraction)
                .animation(spinAnimation, value: rotating)
        }
        .frame(width: 24, height: 24)
        .onAppear { updateRotation() }
        .onChange(of: shouldSpin) { _, _ in updateRotation() }
    }

    private var shouldSpin: Bool {
        progress == nil && !reduceMotion && !settings.batteryOptimizedMode
    }

    private var spinAnimation: Animation? {
        shouldSpin ? .linear(duration: 0.85).repeatForever(autoreverses: false) : nil
    }

    private func updateRotation() {
        rotating = false
        guard shouldSpin else { return }
        withAnimation(spinAnimation) {
            rotating = true
        }
    }
}
