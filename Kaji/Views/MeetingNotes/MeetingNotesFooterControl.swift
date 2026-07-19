import SwiftUI

struct MeetingNotesFooterControl: View {
    let onOpen: () -> Void

    @State private var coordinator = MeetingNotesCoordinator.shared
    @State private var hovered = false

    var body: some View {
        Button(action: performAction) {
            HStack(spacing: 6) {
                footerIcon
                if visualState == .recording {
                    Text(MeetingNotesTimeFormatter.elapsed(coordinator.elapsedDuration))
                        .kajiFont(size: 10, weight: .semibold, design: .monospaced)
                        .foregroundStyle(KajiTheme.fg)
                }
            }
            .frame(minWidth: 28, minHeight: 28)
            .padding(.horizontal, visualState == .recording ? 6 : 0)
            .background(
                KajiControlSurface(
                    base: isActive ? KajiTheme.surface : .clear,
                    cornerRadius: KajiShape.tileRadius,
                    isInteractive: true
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: KajiShape.tileRadius)
                    .strokeBorder(KajiTheme.border.opacity(isActive ? 0.7 : 0), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        }
        .buttonStyle(.borderless)
        .onHover { hovered = $0 }
        .kajiHoverEffect(isActive: isActive)
        .kajiPointer()
        .help(helpText)
        .accessibilityLabel(visualState == .recording ? "Stop meeting recording" : "Open Meeting Notes")
        .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder
    private var footerIcon: some View {
        switch visualState {
        case .idle:
            KajiIcon(systemName: "waveform.and.mic", size: 13)
                .foregroundStyle(KajiTheme.fgMuted)
        case .recording:
            ZStack {
                Circle()
                    .fill(KajiTheme.diffRemoveFg.opacity(0.18))
                    .frame(width: 20, height: 20)
                RoundedRectangle(cornerRadius: 2)
                    .fill(KajiTheme.diffRemoveFg)
                    .frame(width: 8, height: 8)
            }
        case .processing:
            KajiSpinner(size: 13, lineWidth: 1.5, color: KajiTheme.accent)
        case .error:
            KajiIcon(systemName: "exclamationmark.triangle", size: 13)
                .foregroundStyle(KajiTheme.diffHunkFg)
        }
    }

    private var visualState: MeetingNotesFooterVisualState {
        if coordinator.activeDocument != nil {
            return .recording
        }
        return MeetingNotesFooterVisualState.resolve(coordinator.status)
    }

    private var isActive: Bool {
        hovered || visualState != .idle
    }

    private var helpText: String {
        switch visualState {
        case .recording:
            "Stop meeting recording"
        case .processing:
            "Meeting notes are processing"
        case let .error(message):
            "Open Meeting Notes: \(message)"
        case .idle:
            "Open Meeting Notes"
        }
    }

    private var accessibilityValue: String {
        if visualState == .recording {
            return "Recording, \(MeetingNotesTimeFormatter.elapsed(coordinator.elapsedDuration)) elapsed"
        }
        return visualState.accessibilityValue
    }

    private func performAction() {
        if coordinator.activeDocument != nil {
            Task { await coordinator.stop() }
            return
        }
        onOpen()
    }
}
