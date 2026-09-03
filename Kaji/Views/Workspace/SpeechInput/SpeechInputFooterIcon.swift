import SwiftUI

struct SpeechInputFooterIcon: View {
    let state: SpeechInputFooterVisualState
    let active: Bool
    @State private var looping = false
    @State private var settings = TerminalSettingsStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            progressRing
            KajiIcon(systemName: iconName, size: iconSize)
                .foregroundStyle(iconColor)
                .scaleEffect(iconScale)
                .opacity(iconOpacity)
                .rotationEffect(.degrees(rotation))
                .symbolEffect(.pulse, options: .repeating, isActive: usesSymbolPulse)
                .animation(animation, value: looping)
                .animation(KajiMotion.preferred(KajiMotion.fast, reduceMotion: reduceMotion), value: state)
        }
        .onAppear { updateLooping() }
        .onChange(of: state) { _, _ in updateLooping() }
        .onChange(of: shouldLoop) { _, _ in updateLooping() }
    }

    @ViewBuilder
    private var progressRing: some View {
        switch state {
        case let .downloading(progress):
            SpeechInputFooterProgressRing(progress: progress)
        case let .preparing(progress):
            SpeechInputFooterProgressRing(progress: progress)
        default:
            EmptyView()
        }
    }

    private var iconName: String {
        switch state {
        case .disabled:
            "mic.slash"
        case .ready:
            "mic"
        case .requestingPermission:
            "mic.badge.plus"
        case .listening:
            "mic.fill"
        case .transcribing:
            "waveform"
        case .downloading:
            "arrow.down.circle"
        case .preparing:
            "gearshape"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch state {
        case .disabled:
            KajiTheme.fgDim
        case .ready:
            active ? KajiTheme.fg : KajiTheme.fgMuted
        case .failed:
            KajiTheme.diffRemoveFg
        default:
            KajiTheme.accent
        }
    }

    private var iconSize: CGFloat {
        switch state {
        case .failed:
            12
        default:
            13
        }
    }

    private var iconScale: CGFloat {
        guard shouldLoop else { return 1 }
        return switch state {
        case .listening:
            looping ? 1.12 : 0.94
        case .transcribing:
            looping ? 1.08 : 0.96
        case .requestingPermission,
             .downloading:
            looping ? 1.06 : 1
        default:
            1
        }
    }

    private var iconOpacity: Double {
        guard shouldLoop else { return 1 }
        return switch state {
        case .transcribing:
            looping ? 1 : 0.62
        case .requestingPermission:
            looping ? 1 : 0.72
        default:
            1
        }
    }

    private var rotation: Double {
        guard shouldLoop else { return 0 }
        if case .preparing = state {
            return looping ? 360 : 0
        }
        return 0
    }

    private var usesSymbolPulse: Bool {
        guard !reduceMotion, !settings.batteryOptimizedMode else { return false }
        if case .listening = state {
            return true
        }
        return false
    }

    private var shouldLoop: Bool {
        guard !reduceMotion, !settings.batteryOptimizedMode else { return false }
        return switch state {
        case .requestingPermission,
             .listening,
             .transcribing,
             .downloading,
             .preparing: true
        case .disabled,
             .ready,
             .failed: false
        }
    }

    private var animation: Animation? {
        guard shouldLoop else { return nil }
        if case .preparing = state {
            return .linear(duration: 1).repeatForever(autoreverses: false)
        }
        return .easeInOut(duration: 0.72).repeatForever(autoreverses: true)
    }

    private func updateLooping() {
        looping = false
        guard shouldLoop else { return }
        withAnimation(animation) {
            looping = true
        }
    }
}
